package main

import (
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"strconv"
	"strings"
	"time"

	"github.com/spf13/cobra"

	"github.com/oscarangulo/claude-status/internal/analyzer"
	"github.com/oscarangulo/claude-status/internal/config"
	"github.com/oscarangulo/claude-status/internal/model"
)

type budgetConfig struct {
	DailyLimit   float64 `json:"daily_limit"`
	SessionLimit float64 `json:"session_limit"`
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
	b := loadBudget()

	if len(args) == 0 && sessionLimit == 0 {
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
		fmt.Println("\nAlerts fire at 50%, 80%, and 100% of each limit.")
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

	fmt.Println("\nYou'll get alerts at 50%, 80%, and 100% — directly in your Claude Code conversation.")
	return nil
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

	today := time.Now().UTC().Format("2006-01-02")
	var totalCost float64
	var totalTokens int64
	var sessionCount int
	var taskCount int
	var totalCacheRead, totalCacheWrite int64
	var totalInput, totalOutput int64
	var topModel string

	for _, f := range files {
		session, err := model.ParseSessionFile(f)
		if err != nil || session == nil || session.Latest == nil {
			continue
		}

		// Check if session is from today
		if !strings.HasPrefix(session.Latest.Timestamp.Format("2006-01-02"), today) {
			if len(session.Snapshots) > 0 && !strings.HasPrefix(session.Snapshots[0].Timestamp.Format("2006-01-02"), today) {
				continue
			}
		}

		a := analyzer.New()
		a.LoadSession(session)
		s := a.Summary()

		totalCost += s.TotalCost
		totalTokens += s.TotalTokens
		taskCount += s.TaskCount
		sessionCount++
		totalCacheRead += session.Latest.CacheReadTok
		totalCacheWrite += session.Latest.CacheWriteTok
		totalInput += session.Latest.TotalInputTok
		totalOutput += session.Latest.TotalOutputTok
		if topModel == "" {
			topModel = session.Latest.Model
		}
	}

	if sessionCount == 0 {
		fmt.Println("No sessions today.")
		return nil
	}

	// Cache hit rate
	totalIn := totalInput + totalCacheRead
	cacheHit := 0.0
	if totalIn > 0 {
		cacheHit = float64(totalCacheRead) * 100 / float64(totalIn)
	}

	b := loadBudget()

	fmt.Println("═══════════════════════════════════════════")
	fmt.Printf("  Daily Report — %s\n", today)
	fmt.Println("═══════════════════════════════════════════")
	fmt.Println()
	fmt.Printf("  Total spent:    $%.4f\n", totalCost)
	if b.DailyLimit > 0 {
		pct := totalCost * 100 / b.DailyLimit
		remaining := b.DailyLimit - totalCost
		fmt.Printf("  Budget:         $%.2f (%.0f%% used, $%.2f remaining)\n", b.DailyLimit, pct, remaining)
	}
	fmt.Printf("  Sessions:       %d\n", sessionCount)
	fmt.Printf("  Tasks:          %d\n", taskCount)
	fmt.Printf("  Model:          %s\n", topModel)
	fmt.Println()
	fmt.Printf("  Tokens:         %s total\n", formatTokens(totalTokens))
	fmt.Printf("  Input:          %s\n", formatTokens(totalInput))
	fmt.Printf("  Output:         %s\n", formatTokens(totalOutput))
	fmt.Printf("  Cache read:     %s\n", formatTokens(totalCacheRead))
	fmt.Printf("  Cache write:    %s\n", formatTokens(totalCacheWrite))
	fmt.Printf("  Cache hit:      %.0f%%\n", cacheHit)
	fmt.Println()

	if taskCount > 0 {
		avgCost := totalCost / float64(taskCount)
		fmt.Printf("  Avg cost/task:  $%.4f\n", avgCost)
	}
	if sessionCount > 0 {
		avgCost := totalCost / float64(sessionCount)
		fmt.Printf("  Avg cost/sess:  $%.4f\n", avgCost)
	}

	fmt.Println()

	// Tips
	if cacheHit < 30 {
		fmt.Println("  Tip: Low cache hit rate. Use consistent prompts and structured plans.")
	}
	if totalCost > 0 && totalOutput > 0 {
		ratio := float64(totalOutput) / float64(totalInput)
		if ratio > 0.5 {
			fmt.Println("  Tip: High output ratio. Consider more targeted requests.")
		}
	}
	if b.DailyLimit > 0 && totalCost > b.DailyLimit*0.8 {
		fmt.Println("  Tip: Close to daily limit. Use Sonnet/Haiku for lighter tasks.")
	}

	fmt.Println("═══════════════════════════════════════════")
	return nil
}
