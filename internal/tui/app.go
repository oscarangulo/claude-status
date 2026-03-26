package tui

import (
	"context"

	"github.com/charmbracelet/bubbles/key"
	tea "github.com/charmbracelet/bubbletea"
	"github.com/oscarandresrodriguez/claude-status/internal/analyzer"
	"github.com/oscarandresrodriguez/claude-status/internal/model"
	"github.com/oscarandresrodriguez/claude-status/internal/watcher"
)

// Messages
type snapshotMsg model.Snapshot
type taskEventMsg model.TaskEvent

type App struct {
	analyzer *analyzer.Analyzer
	watcher  *watcher.Watcher
	cancel   context.CancelFunc
	width    int
	height   int
	ready    bool
}

func NewApp(a *analyzer.Analyzer, w *watcher.Watcher) *App {
	return &App{
		analyzer: a,
		watcher:  w,
	}
}

func (app *App) Init() tea.Cmd {
	ctx, cancel := context.WithCancel(context.Background())
	app.cancel = cancel

	if err := app.watcher.Start(ctx); err != nil {
		// Watcher failed, continue without live updates
		return nil
	}

	return tea.Batch(
		waitForSnapshot(app.watcher),
		waitForTaskEvent(app.watcher),
	)
}

func (app *App) Update(msg tea.Msg) (tea.Model, tea.Cmd) {
	switch msg := msg.(type) {
	case tea.WindowSizeMsg:
		app.width = msg.Width
		app.height = msg.Height
		app.ready = true
		return app, nil

	case tea.KeyMsg:
		switch {
		case key.Matches(msg, keys.Quit):
			if app.cancel != nil {
				app.cancel()
			}
			return app, tea.Quit
		case key.Matches(msg, keys.Refresh):
			return app, nil
		}

	case snapshotMsg:
		app.analyzer.AddSnapshot(model.Snapshot(msg))
		return app, waitForSnapshot(app.watcher)

	case taskEventMsg:
		app.analyzer.AddTaskEvent(model.TaskEvent(msg))
		return app, waitForTaskEvent(app.watcher)
	}

	return app, nil
}

func (app *App) View() string {
	if !app.ready {
		return "Starting claude-status...\n"
	}
	return renderDashboard(app.analyzer, app.width)
}

// waitForSnapshot creates a command that waits for the next snapshot from the watcher.
func waitForSnapshot(w *watcher.Watcher) tea.Cmd {
	return func() tea.Msg {
		snap, ok := <-w.Snapshots()
		if !ok {
			return nil
		}
		return snapshotMsg(snap)
	}
}

// waitForTaskEvent creates a command that waits for the next task event from the watcher.
func waitForTaskEvent(w *watcher.Watcher) tea.Cmd {
	return func() tea.Msg {
		evt, ok := <-w.TaskEvents()
		if !ok {
			return nil
		}
		return taskEventMsg(evt)
	}
}
