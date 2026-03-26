package watcher

import (
	"context"
	"os"
	"path/filepath"
	"sync"
	"time"

	"github.com/fsnotify/fsnotify"
	"github.com/oscarandresrodriguez/claude-status/internal/model"
)

type Watcher struct {
	sessionDir string
	snapCh     chan model.Snapshot
	taskCh     chan model.TaskEvent
	offsets    map[string]int64
	mu         sync.Mutex
}

func New(sessionDir string) *Watcher {
	return &Watcher{
		sessionDir: sessionDir,
		snapCh:     make(chan model.Snapshot, 64),
		taskCh:     make(chan model.TaskEvent, 64),
		offsets:    make(map[string]int64),
	}
}

func (w *Watcher) Snapshots() <-chan model.Snapshot  { return w.snapCh }
func (w *Watcher) TaskEvents() <-chan model.TaskEvent { return w.taskCh }

// Start watches the sessions directory for new/modified JSONL files.
func (w *Watcher) Start(ctx context.Context) error {
	fsw, err := fsnotify.NewWatcher()
	if err != nil {
		return err
	}

	if err := os.MkdirAll(w.sessionDir, 0755); err != nil {
		return err
	}

	if err := fsw.Add(w.sessionDir); err != nil {
		fsw.Close()
		return err
	}

	go func() {
		defer fsw.Close()
		defer close(w.snapCh)
		defer close(w.taskCh)

		// Debounce: batch rapid writes
		timer := time.NewTimer(0)
		if !timer.Stop() {
			<-timer.C
		}
		var pendingFiles map[string]struct{}
		pendingFiles = make(map[string]struct{})

		for {
			select {
			case <-ctx.Done():
				return
			case event, ok := <-fsw.Events:
				if !ok {
					return
				}
				if event.Op&(fsnotify.Write|fsnotify.Create) == 0 {
					continue
				}
				if filepath.Ext(event.Name) != ".jsonl" {
					continue
				}
				pendingFiles[event.Name] = struct{}{}
				timer.Reset(50 * time.Millisecond)

			case <-timer.C:
				for path := range pendingFiles {
					w.processFile(path)
				}
				pendingFiles = make(map[string]struct{})

			case _, ok := <-fsw.Errors:
				if !ok {
					return
				}
			}
		}
	}()

	return nil
}

func (w *Watcher) processFile(path string) {
	f, err := os.Open(path)
	if err != nil {
		return
	}
	defer f.Close()

	w.mu.Lock()
	offset := w.offsets[path]
	w.mu.Unlock()

	snaps, events, newOffset, err := model.ParseNewLines(f, offset)
	if err != nil {
		return
	}

	w.mu.Lock()
	w.offsets[path] = newOffset
	w.mu.Unlock()

	for _, s := range snaps {
		select {
		case w.snapCh <- s:
		default: // drop if channel full
		}
	}
	for _, e := range events {
		select {
		case w.taskCh <- e:
		default:
		}
	}
}

// SetOffset allows pre-setting the offset for a file (e.g., after initial parse).
func (w *Watcher) SetOffset(path string, offset int64) {
	w.mu.Lock()
	w.offsets[path] = offset
	w.mu.Unlock()
}
