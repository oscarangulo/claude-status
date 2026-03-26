package main

import (
	"embed"
	"fmt"
	"os"

	tea "github.com/charmbracelet/bubbletea"
	"github.com/spf13/cobra"

	"github.com/oscarangulo/claude-status/internal/analyzer"
	"github.com/oscarangulo/claude-status/internal/config"
	"github.com/oscarangulo/claude-status/internal/installer"
	"github.com/oscarangulo/claude-status/internal/model"
	"github.com/oscarangulo/claude-status/internal/tui"
	"github.com/oscarangulo/claude-status/internal/watcher"
)

var version = "dev"

//go:embed hooks
var hookFiles embed.FS

func main() {
	installer.HookFiles = hookFiles

	rootCmd := &cobra.Command{
		Use:     "claude-status",
		Short:   "Real-time token usage and cost dashboard for Claude Code",
		Long:    "Monitor your Claude Code sessions in real-time. See token usage, cost breakdowns per task, and optimization tips.",
		Version: version,
		RunE:    runDashboard,
	}

	installCmd := &cobra.Command{
		Use:   "install",
		Short: "Install hooks into Claude Code settings",
		Long:  "Configures Claude Code with the status-line and task-tracking hooks needed for monitoring.",
		RunE: func(cmd *cobra.Command, args []string) error {
			fmt.Printf("claude-status %s\n\n", version)
			return installer.Install()
		},
	}

	uninstallCmd := &cobra.Command{
		Use:   "uninstall",
		Short: "Remove hooks from Claude Code settings",
		Long:  "Removes status-line and task-tracking hooks from Claude Code. Session data is preserved.",
		RunE: func(cmd *cobra.Command, args []string) error {
			return installer.Uninstall()
		},
	}

	updateCmd := &cobra.Command{
		Use:   "update",
		Short: "Update hook scripts to the latest version",
		Long:  "Re-installs hook scripts from the current binary. Run this after upgrading claude-status to get the latest status line features.",
		RunE: func(cmd *cobra.Command, args []string) error {
			fmt.Printf("claude-status %s\n\n", version)
			fmt.Println("Updating hook scripts...")
			return installer.Install()
		},
	}

	historyCmd := &cobra.Command{
		Use:   "history",
		Short: "Show past session summaries",
		RunE:  runHistory,
	}

	rootCmd.AddCommand(installCmd, uninstallCmd, updateCmd, historyCmd)

	if err := rootCmd.Execute(); err != nil {
		os.Exit(1)
	}
}

func runDashboard(cmd *cobra.Command, args []string) error {
	cfg := config.Default()
	if err := cfg.EnsureDirs(); err != nil {
		return fmt.Errorf("cannot create data directories: %w", err)
	}

	a := analyzer.New()
	w := watcher.New(cfg.SessionDir)

	activeFile, err := cfg.ActiveSessionFile()
	if err != nil {
		return fmt.Errorf("cannot find session files: %w", err)
	}

	if activeFile != "" {
		session, err := model.ParseSessionFile(activeFile)
		if err == nil && session != nil {
			a.LoadSession(session)
			if info, err := os.Stat(activeFile); err == nil {
				w.SetOffset(activeFile, info.Size())
			}
		}
	}

	app := tui.NewApp(a, w)
	p := tea.NewProgram(app, tea.WithAltScreen())
	_, err = p.Run()
	return err
}

func runHistory(cmd *cobra.Command, args []string) error {
	cfg := config.Default()

	files, err := cfg.SessionFiles()
	if err != nil {
		return fmt.Errorf("cannot list sessions: %w", err)
	}

	if len(files) == 0 {
		fmt.Println("No sessions found. Run 'claude-status install' and start a Claude Code session first.")
		return nil
	}

	fmt.Println("Session History")
	fmt.Printf("%-20s %-10s %-12s %-10s %s\n", "Session", "Cost", "Tokens", "Tasks", "Cache Hit")
	fmt.Println("─────────────────────────────────────────────────────────────────")

	for _, f := range files {
		session, err := model.ParseSessionFile(f)
		if err != nil || session == nil {
			continue
		}

		a := analyzer.New()
		a.LoadSession(session)
		s := a.Summary()

		id := s.SessionID
		if len(id) > 16 {
			id = id[:16]
		}

		fmt.Printf("%-20s $%-9.4f %-12s %-10d %.0f%%\n",
			id, s.TotalCost, formatTokens(s.TotalTokens), s.TaskCount, s.CacheHitRate)
	}

	return nil
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
