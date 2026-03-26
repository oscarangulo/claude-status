package tui

import (
	"fmt"
	"strings"

	"github.com/oscarandresrodriguez/claude-status/internal/analyzer"
	"github.com/oscarandresrodriguez/claude-status/internal/model"
)

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

func renderTips(tips []string, width int) string {
	title := titleStyle.Render("Tips")

	var lines []string
	for _, tip := range tips {
		lines = append(lines, "  "+tipStyle.Render("• "+tip))
	}

	return title + "\n" + strings.Join(lines, "\n")
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
