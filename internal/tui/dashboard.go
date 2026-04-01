package tui

import (
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"strings"
	"time"

	"github.com/oscarangulo/claude-status/internal/analyzer"
	"github.com/oscarangulo/claude-status/internal/model"
)

type budgetConfig struct {
	DailyLimit   float64 `json:"daily_limit"`
	SessionLimit float64 `json:"session_limit"`
	PulseEvery   int     `json:"pulse_every,omitempty"`
}

func renderDashboard(a *analyzer.Analyzer, width int) string {
	if width < 40 {
		width = 80
	}
	innerWidth := width - 4

	var b strings.Builder

	summary := a.Summary()
	taskCosts := a.TaskCosts()
	tips := a.Tips()

	// Header
	header := renderHeader(summary, innerWidth)
	b.WriteString(headerStyle.Width(innerWidth).Render(header))
	b.WriteString("\n")

	// Budget
	if budget := renderBudget(summary.TotalCost, innerWidth); budget != "" {
		b.WriteString(sectionStyle.Width(innerWidth).Render(budget))
		b.WriteString("\n")
	}

	// Context bar
	ctxBar := renderContextBar(summary.ContextUsedPct, innerWidth)
	b.WriteString(sectionStyle.Width(innerWidth).Render(ctxBar))
	b.WriteString("\n")

	// Token breakdown
	tokenBreak := renderTokenBreakdown(summary, innerWidth)
	b.WriteString(sectionStyle.Width(innerWidth).Render(tokenBreak))
	b.WriteString("\n")

	// Task table
	if len(taskCosts) > 0 {
		taskTable := renderTaskTable(taskCosts, summary.TotalCost, innerWidth)
		b.WriteString(sectionStyle.Width(innerWidth).Render(taskTable))
		b.WriteString("\n")
	}

	// Subagent table
	if subagents := a.Session().SubagentEvents; len(subagents) > 0 {
		subTable := renderSubagentTable(subagents, innerWidth)
		b.WriteString(sectionStyle.Width(innerWidth).Render(subTable))
		b.WriteString("\n")
	}

	// Tips
	if len(tips) > 0 {
		tipsSection := renderTips(tips, innerWidth)
		b.WriteString(sectionStyle.Width(innerWidth).Render(tipsSection))
		b.WriteString("\n")
	}

	// Footer
	b.WriteString(footerStyle.Render("  q: quit  r: refresh  ?: help"))

	return b.String()
}

func renderHeader(s model.SessionSummary, width int) string {
	title := titleStyle.Render("Claude Status")
	modelStr := ""
	if s.Model != "" {
		modelStr = labelStyle.Render(" | ") + valueStyle.Render(s.Model)
	}

	cost := costStyle.Render(fmt.Sprintf("$%.4f", s.TotalCost))
	tokens := valueStyle.Render(formatTokens(s.TotalTokens))
	duration := ""
	if s.Duration > 0 {
		duration = labelStyle.Render(" | ") + valueStyle.Render(s.Duration.Round(1e9).String())
	}

	line1 := title + modelStr
	line2 := labelStyle.Render("Cost: ") + cost +
		labelStyle.Render("  Tokens: ") + tokens +
		duration

	lines := ""
	if s.LinesAdded > 0 || s.LinesRemoved > 0 {
		lines = labelStyle.Render("  Code: ") +
			valueStyle.Render(fmt.Sprintf("+%d", s.LinesAdded)) +
			labelStyle.Render("/") +
			dangerStyle.Render(fmt.Sprintf("-%d", s.LinesRemoved))
	}

	return line1 + "\n" + line2 + lines
}

func renderContextBar(pct float64, width int) string {
	barWidth := width - 20
	if barWidth < 10 {
		barWidth = 10
	}

	filled := int(pct / 100 * float64(barWidth))
	if filled > barWidth {
		filled = barWidth
	}

	bar := barFilledStyle.Render(strings.Repeat("█", filled)) +
		barEmptyStyle.Render(strings.Repeat("░", barWidth-filled))

	pctStr := fmt.Sprintf("%.0f%%", pct)
	style := valueStyle
	if pct > 80 {
		style = dangerStyle
	} else if pct > 60 {
		style = warnStyle
	}

	return labelStyle.Render("Context: ") + bar + " " + style.Render(pctStr)
}

func renderTokenBreakdown(s model.SessionSummary, width int) string {
	title := titleStyle.Render("Token Breakdown")

	input := labelStyle.Render("  Input:       ") + valueStyle.Render(formatTokens(s.InputTokens))
	output := labelStyle.Render("  Output:      ") + valueStyle.Render(formatTokens(s.OutputTokens))
	cacheR := labelStyle.Render("  Cache Read:  ") + valueStyle.Render(formatTokens(s.CacheReadTok))
	cacheW := labelStyle.Render("  Cache Write: ") + valueStyle.Render(formatTokens(s.CacheWriteTok))

	cacheRate := labelStyle.Render("  Cache Hit:   ")
	if s.CacheHitRate > 50 {
		cacheRate += costStyle.Render(fmt.Sprintf("%.0f%%", s.CacheHitRate))
	} else if s.CacheHitRate > 20 {
		cacheRate += warnStyle.Render(fmt.Sprintf("%.0f%%", s.CacheHitRate))
	} else {
		cacheRate += dangerStyle.Render(fmt.Sprintf("%.0f%%", s.CacheHitRate))
	}

	return title + "\n" + input + "\n" + output + "\n" + cacheR + "\n" + cacheW + "\n" + cacheRate
}

func renderTaskTable(tasks []model.TaskCost, totalCost float64, width int) string {
	title := titleStyle.Render("Plan Tasks")

	var rows []string
	for _, t := range tasks {
		var icon string
		var nameStyle func(strs ...string) string
		switch t.Status {
		case "completed":
			icon = taskCompleteStyle.Render("✓")
			nameStyle = taskCompleteStyle.Render
		case "running":
			icon = taskRunningStyle.Render("●")
			nameStyle = taskRunningStyle.Render
		default:
			icon = taskPendingStyle.Render("○")
			nameStyle = taskPendingStyle.Render
		}

		// Truncate subject if too long
		subject := t.Subject
		maxSubj := width - 40
		if maxSubj < 20 {
			maxSubj = 20
		}
		if len(subject) > maxSubj {
			subject = subject[:maxSubj-3] + "..."
		}

		// Cost bar (proportional)
		barWidth := 10
		var filled int
		if totalCost > 0 {
			filled = int(t.Percentage / 100 * float64(barWidth))
		}
		if filled > barWidth {
			filled = barWidth
		}
		bar := barFilledStyle.Render(strings.Repeat("█", filled)) +
			barEmptyStyle.Render(strings.Repeat("░", barWidth-filled))

		cost := fmt.Sprintf("$%.4f", t.DeltaCost)
		pct := fmt.Sprintf("%.0f%%", t.Percentage)

		row := fmt.Sprintf("  %s %s  %s  %s %s",
			icon, nameStyle(fmt.Sprintf("%-*s", maxSubj, subject)),
			costStyle.Render(cost), bar, labelStyle.Render(pct))
		rows = append(rows, row)
	}

	return title + "\n" + strings.Join(rows, "\n")
}

func renderSubagentTable(events []model.SubagentEvent, width int) string {
	title := titleStyle.Render("Subagents")

	var totalCost float64
	for _, e := range events {
		totalCost += e.CostUSD
	}

	title += labelStyle.Render(fmt.Sprintf(" (%d)", len(events))) +
		labelStyle.Render("  Total: ") + costStyle.Render(fmt.Sprintf("$%.4f", totalCost))

	var rows []string
	for _, e := range events {
		agentType := e.AgentType
		maxType := 15
		if len(agentType) > maxType {
			agentType = agentType[:maxType-3] + "..."
		}

		cost := costStyle.Render(fmt.Sprintf("$%.4f", e.CostUSD))
		model := labelStyle.Render(e.Model)

		row := fmt.Sprintf("  %s  %-*s  %s  %s",
			valueStyle.Render("▸"), maxType, agentType, cost, model)
		rows = append(rows, row)
	}

	return title + "\n" + strings.Join(rows, "\n")
}

func renderTips(tips []string, width int) string {
	title := titleStyle.Render("Tips")

	var lines []string
	for _, tip := range tips {
		lines = append(lines, "  "+tipStyle.Render("• "+tip))
	}

	return title + "\n" + strings.Join(lines, "\n")
}

func loadBudget() budgetConfig {
	home, err := os.UserHomeDir()
	if err != nil {
		return budgetConfig{}
	}
	data, err := os.ReadFile(filepath.Join(home, ".claude-status", "budget.json"))
	if err != nil {
		return budgetConfig{}
	}
	var b budgetConfig
	json.Unmarshal(data, &b)
	return b
}

func dailySpend() float64 {
	home, err := os.UserHomeDir()
	if err != nil {
		return 0
	}
	sessDir := filepath.Join(home, ".claude-status", "sessions")
	entries, err := os.ReadDir(sessDir)
	if err != nil {
		return 0
	}
	today := time.Now().Format("2006-01-02")
	var total float64
	for _, e := range entries {
		if e.IsDir() || !strings.HasSuffix(e.Name(), ".jsonl") {
			continue
		}
		info, err := e.Info()
		if err != nil || info.ModTime().Format("2006-01-02") != today {
			continue
		}
		data, err := os.ReadFile(filepath.Join(sessDir, e.Name()))
		if err != nil {
			continue
		}
		lines := strings.Split(strings.TrimSpace(string(data)), "\n")
		for i := len(lines) - 1; i >= 0; i-- {
			if strings.Contains(lines[i], `"type":"snapshot"`) {
				var snap struct {
					Cost float64 `json:"total_cost_usd"`
				}
				if json.Unmarshal([]byte(lines[i]), &snap) == nil {
					total += snap.Cost
				}
				break
			}
		}
	}
	return total
}

func renderBudget(sessionCost float64, width int) string {
	b := loadBudget()
	if b.DailyLimit <= 0 {
		return ""
	}

	title := titleStyle.Render("Budget")

	totalToday := dailySpend()
	if totalToday < sessionCost {
		totalToday = sessionCost
	}

	pct := totalToday * 100 / b.DailyLimit
	remaining := b.DailyLimit - totalToday
	if remaining < 0 {
		remaining = 0
	}

	barWidth := width - 20
	if barWidth < 10 {
		barWidth = 10
	}
	filled := int(pct / 100 * float64(barWidth))
	if filled > barWidth {
		filled = barWidth
	}
	bar := barFilledStyle.Render(strings.Repeat("█", filled)) +
		barEmptyStyle.Render(strings.Repeat("░", barWidth-filled))

	pctStr := fmt.Sprintf("%.0f%%", pct)
	style := costStyle
	if pct >= 100 {
		style = dangerStyle
	} else if pct >= 80 {
		style = warnStyle
	}

	line1 := labelStyle.Render("  Daily:     ") + bar + " " + style.Render(pctStr)
	line2 := labelStyle.Render("  Spent:     ") + costStyle.Render(fmt.Sprintf("$%.2f", totalToday)) +
		labelStyle.Render(" / ") + valueStyle.Render(fmt.Sprintf("$%.2f", b.DailyLimit)) +
		labelStyle.Render("  Remaining: ") + valueStyle.Render(fmt.Sprintf("$%.2f", remaining))

	return title + "\n" + line1 + "\n" + line2
}

func formatTokens(n int64) string {
	if n >= 1_000_000 {
		return fmt.Sprintf("%.1fM", float64(n)/1_000_000)
	}
	if n >= 1_000 {
		return fmt.Sprintf("%.1fK", float64(n)/1_000)
	}
	return fmt.Sprintf("%d", n)
}
