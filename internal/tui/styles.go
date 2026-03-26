package tui

import "github.com/charmbracelet/lipgloss"

var (
	// Colors
	orange    = lipgloss.Color("#E67E22")
	green     = lipgloss.Color("#2ECC71")
	yellow    = lipgloss.Color("#F1C40F")
	red       = lipgloss.Color("#E74C3C")
	blue      = lipgloss.Color("#3498DB")
	dimWhite  = lipgloss.Color("#95A5A6")
	white     = lipgloss.Color("#ECF0F1")
	darkGray  = lipgloss.Color("#2C3E50")
	medGray   = lipgloss.Color("#7F8C8D")

	// Box styles
	headerStyle = lipgloss.NewStyle().
			Bold(true).
			Foreground(orange).
			BorderStyle(lipgloss.RoundedBorder()).
			BorderForeground(orange).
			Padding(0, 1)

	sectionStyle = lipgloss.NewStyle().
			BorderStyle(lipgloss.RoundedBorder()).
			BorderForeground(dimWhite).
			Padding(0, 1)

	titleStyle = lipgloss.NewStyle().
			Bold(true).
			Foreground(white)

	labelStyle = lipgloss.NewStyle().
			Foreground(dimWhite)

	valueStyle = lipgloss.NewStyle().
			Bold(true).
			Foreground(white)

	costStyle = lipgloss.NewStyle().
			Bold(true).
			Foreground(green)

	warnStyle = lipgloss.NewStyle().
			Foreground(yellow)

	dangerStyle = lipgloss.NewStyle().
			Foreground(red)

	tipStyle = lipgloss.NewStyle().
			Foreground(blue).
			Italic(true)

	taskRunningStyle = lipgloss.NewStyle().
				Foreground(yellow).
				Bold(true)

	taskCompleteStyle = lipgloss.NewStyle().
				Foreground(green)

	taskPendingStyle = lipgloss.NewStyle().
				Foreground(dimWhite)

	barFilledStyle = lipgloss.NewStyle().
			Foreground(orange)

	barEmptyStyle = lipgloss.NewStyle().
			Foreground(darkGray)

	footerStyle = lipgloss.NewStyle().
			Foreground(medGray)
)
