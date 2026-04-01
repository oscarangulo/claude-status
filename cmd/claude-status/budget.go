package main

import (
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"strconv"
	"time"

	"github.com/spf13/cobra"

	"github.com/oscarangulo/claude-status/internal/analyzer"
	"github.com/oscarangulo/claude-status/internal/config"
	"github.com/oscarangulo/claude-status/internal/model"
)

type budgetConfig struct {
	DailyLimit   float64 `json:"daily_limit"`
	SessionLimit float64 `json:"session_limit"`
	PulseEvery   int     `json:"pulse_every,omitempty"`
	Plan         string  `json:"plan,omitempty"` // "pro" for subscription plans (skips cost alerts)
}

func budgetFilePath() string {
	home, _ := os.UserHomeDir()
	return filepath.Join(home, ".claude-status", "budget.json")
}

func loadBudget() budgetConfig {
	data, err := os.ReadFile(budgetFilePath())
	if err != nil {
		return budgetConfig{}
	}
	var b budgetConfig
	json.Unmarshal(data, &b)
	return b
}

func saveBudget(b budgetConfig) error {
	data, err := json.MarshalIndent(b, "", "  ")
	if err != nil {
		return err
	}
	return os.WriteFile(budgetFilePath(), data, 0644)
}

func runBudget(cmd *cobra.Command, args []string) error {
	sessionLimit, _ := cmd.Flags().GetFloat64("session")
	pulseEvery, _ := cmd.Flags().GetInt("pulse")
	planMode, _ := cmd.Flags().GetString("plan")
	b := loadBudget()

	if len(args) == 0 && sessionLimit == 0 && pulseEvery == 0 && planMode == "" {
		// Show current budget
		if b.DailyLimit == 0 && b.SessionLimit == 0 {
			fmt.Println("No budget set. Usage:")
			fmt.Println("  claude-status budget 20        # $20/day limit")
			fmt.Println("  claude-status budget --session 5  # $5/session limit")
			fmt.Println("  claude-status budget 0         # disable daily limit")
			return nil
		}
		if b.DailyLimit > 0 {
			fmt.Printf("Daily limit:   $%.2f\n", b.DailyLimit)
		}
		if b.SessionLimit > 0 {
			fmt.Printf("Session limit: $%.2f\n", b.SessionLimit)
		}
		if b.PulseEvery > 0 {
			fmt.Printf("Cost pulse:    every %d tool calls\n", b.PulseEvery)
		} else {
			fmt.Println("Cost pulse:    every 3 tool calls (default)")
		}
		if b.Plan == "api" {
			fmt.Println("Plan:          api (cost alerts at 50%, 80%, 100%)")
		} else {
			fmt.Println("Plan:          pro (productivity pulse, no cost alerts)")
		}
		fmt.Println("\nAlerts appear directly in your Claude Code conversation.")
		return nil
	}

	if len(args) > 0 {
		limit, err := strconv.ParseFloat(args[0], 64)
		if err != nil {
			return fmt.Errorf("invalid amount %q: %w", args[0], err)
		}
		b.DailyLimit = limit
	}

	if sessionLimit > 0 {
		b.SessionLimit = sessionLimit
	}

	if pulseEvery > 0 {
		b.PulseEvery = pulseEvery
	}

	if planMode != "" {
		if planMode == "pro" || planMode == "api" {
			b.Plan = planMode
		} else {
			return fmt.Errorf("invalid plan %q: use 'pro' (subscription) or 'api' (pay-per-token)", planMode)
		}
	}

	if err := saveBudget(b); err != nil {
		return fmt.Errorf("cannot save budget: %w", err)
	}

	if b.DailyLimit > 0 {
		fmt.Printf("Daily limit set to $%.2f\n", b.DailyLimit)
	} else {
		fmt.Println("Daily limit disabled.")
	}
	if b.SessionLimit > 0 {
		fmt.Printf("Session limit set to $%.2f\n", b.SessionLimit)
	}
	if b.PulseEvery > 0 {
		fmt.Printf("Cost pulse every %d tool calls\n", b.PulseEvery)
	}
	if b.Plan == "pro" {
		fmt.Println("Plan: pro (subscription — cost alerts disabled, productivity pulse enabled)")
	}

	fmt.Println("\nAlerts appear directly in your Claude Code conversation.")
	return nil
}

// reportData holds aggregated metrics for a time period.
type reportData struct {
	totalCost      float64
	totalTokens    int64
	sessionCount   int
	taskCount      int
	totalCacheRead int64
	totalCacheWrite int64
	totalInput     int64
	totalOutput    int64
	topModel       string
}

func aggregateSessions(files []string, startDate, endDate string) reportData {
	var d reportData
	for _, f := range files {
		session, err := model.ParseSessionFile(f)
		if err != nil || session == nil || session.Latest == nil {
			continue
		}

		sessionDate := session.Latest.Timestamp.Format("2006-01-02")
		if sessionDate < startDate || sessionDate > endDate {
			if len(session.Snapshots) == 0 {
				continue
			}
			firstDate := session.Snapshots[0].Timestamp.Format("2006-01-02")
			if firstDate < startDate || firstDate > endDate {
				continue
			}
		}

		a := analyzer.New()
		a.LoadSession(session)
		s := a.Summary()

		d.totalCost += s.TotalCost
		d.totalTokens += s.TotalTokens
		d.taskCount += s.TaskCount
		d.sessionCount++
		d.totalCacheRead += session.Latest.CacheReadTok
		d.totalCacheWrite += session.Latest.CacheWriteTok
		d.totalInput += session.Latest.TotalInputTok
		d.totalOutput += session.Latest.TotalOutputTok
		if d.topModel == "" {
			d.topModel = session.Latest.Model
		}
	}
	return d
}

func printReport(title string, d reportData, b budgetConfig, budgetDays int) {
	totalIn := d.totalInput + d.totalCacheRead
	cacheHit := 0.0
	if totalIn > 0 {
		cacheHit = float64(d.totalCacheRead) * 100 / float64(totalIn)
	}

	fmt.Println("═══════════════════════════════════════════")
	fmt.Printf("  %s\n", title)
	fmt.Println("═══════════════════════════════════════════")
	fmt.Println()
	fmt.Printf("  Total spent:    $%.4f\n", d.totalCost)
	if b.DailyLimit > 0 && budgetDays > 0 {
		totalBudget := b.DailyLimit * float64(budgetDays)
		pct := d.totalCost * 100 / totalBudget
		remaining := totalBudget - d.totalCost
		fmt.Printf("  Budget:         $%.2f (%.0f%% used, $%.2f remaining)\n", totalBudget, pct, remaining)
	}
	fmt.Printf("  Sessions:       %d\n", d.sessionCount)
	fmt.Printf("  Tasks:          %d\n", d.taskCount)
	fmt.Printf("  Model:          %s\n", d.topModel)
	fmt.Println()
	fmt.Printf("  Tokens:         %s total\n", formatTokens(d.totalTokens))
	fmt.Printf("  Input:          %s\n", formatTokens(d.totalInput))
	fmt.Printf("  Output:         %s\n", formatTokens(d.totalOutput))
	fmt.Printf("  Cache read:     %s\n", formatTokens(d.totalCacheRead))
	fmt.Printf("  Cache write:    %s\n", formatTokens(d.totalCacheWrite))
	fmt.Printf("  Cache hit:      %.0f%%\n", cacheHit)
	fmt.Println()

	if d.taskCount > 0 {
		fmt.Printf("  Avg cost/task:  $%.4f\n", d.totalCost/float64(d.taskCount))
	}
	if d.sessionCount > 0 {
		fmt.Printf("  Avg cost/sess:  $%.4f\n", d.totalCost/float64(d.sessionCount))
	}
	if budgetDays > 1 {
		fmt.Printf("  Avg cost/day:   $%.4f\n", d.totalCost/float64(budgetDays))
	}

	fmt.Println()

	// Tips
	if cacheHit < 30 {
		fmt.Println("  Tip: Low cache hit rate. Use consistent prompts and structured plans.")
	}
	if d.totalCost > 0 && d.totalOutput > 0 {
		ratio := float64(d.totalOutput) / float64(d.totalInput)
		if ratio > 0.5 {
			fmt.Println("  Tip: High output ratio. Consider more targeted requests.")
		}
	}
	if b.DailyLimit > 0 && budgetDays == 1 && d.totalCost > b.DailyLimit*0.8 {
		fmt.Println("  Tip: Close to daily limit. Use Sonnet/Haiku for lighter tasks.")
	}

	fmt.Println("═══════════════════════════════════════════")
}

func runReport(cmd *cobra.Command, args []string) error {
	cfg := config.Default()
	files, err := cfg.SessionFiles()
	if err != nil {
		return fmt.Errorf("cannot list sessions: %w", err)
	}

	if len(files) == 0 {
		fmt.Println("No sessions found.")
		return nil
	}

	isWeek, _ := cmd.Flags().GetBool("week")
	b := loadBudget()

	if isWeek {
		now := time.Now().UTC()
		// Go back to Monday of this week
		weekday := int(now.Weekday())
		if weekday == 0 {
			weekday = 7
		}
		monday := now.AddDate(0, 0, -(weekday - 1))
		startDate := monday.Format("2006-01-02")
		endDate := now.Format("2006-01-02")
		days := weekday

		d := aggregateSessions(files, startDate, endDate)
		if d.sessionCount == 0 {
			fmt.Println("No sessions this week.")
			return nil
		}

		title := fmt.Sprintf("Weekly Report — %s to %s (%d days)", startDate, endDate, days)
		printReport(title, d, b, days)

		// Show per-day breakdown
		fmt.Println()
		fmt.Printf("  %-12s %10s %8s %8s\n", "Day", "Cost", "Sessions", "Tasks")
		fmt.Println("  ──────────────────────────────────────────")
		for i := 0; i < days; i++ {
			day := monday.AddDate(0, 0, i)
			dayStr := day.Format("2006-01-02")
			dd := aggregateSessions(files, dayStr, dayStr)
			if dd.sessionCount > 0 {
				fmt.Printf("  %-12s %9s %8d %8d\n", day.Format("Mon 01/02"), fmt.Sprintf("$%.2f", dd.totalCost), dd.sessionCount, dd.taskCount)
			} else {
				fmt.Printf("  %-12s %10s %8s %8s\n", day.Format("Mon 01/02"), "—", "—", "—")
			}
		}
		fmt.Println("═══════════════════════════════════════════")
		return nil
	}

	// Daily report (default)
	today := time.Now().UTC().Format("2006-01-02")
	d := aggregateSessions(files, today, today)
	if d.sessionCount == 0 {
		fmt.Println("No sessions today.")
		return nil
	}

	title := fmt.Sprintf("Daily Report — %s", today)
	printReport(title, d, b, 1)
	return nil
}
