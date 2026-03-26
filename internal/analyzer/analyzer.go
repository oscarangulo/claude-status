package analyzer

import (
	"fmt"
	"sort"
	"time"

	"github.com/oscarandresrodriguez/claude-status/internal/model"
)

type Analyzer struct {
	session *model.Session
}

func New() *Analyzer {
	return &Analyzer{
		session: &model.Session{},
	}
}

func (a *Analyzer) Session() *model.Session { return a.session }

func (a *Analyzer) AddSnapshot(snap model.Snapshot) {
	a.session.Snapshots = append(a.session.Snapshots, snap)
	a.session.Latest = &a.session.Snapshots[len(a.session.Snapshots)-1]
	if a.session.ID == "" && snap.SessionID != "" {
		a.session.ID = snap.SessionID
	}
	if a.session.StartedAt.IsZero() {
		a.session.StartedAt = snap.Timestamp
	}
}

func (a *Analyzer) AddTaskEvent(evt model.TaskEvent) {
	a.session.TaskEvents = append(a.session.TaskEvents, evt)
}

func (a *Analyzer) LoadSession(s *model.Session) {
	a.session = s
}

// TaskCosts computes the cost breakdown per task by correlating task events with snapshots.
func (a *Analyzer) TaskCosts() []model.TaskCost {
	if len(a.session.TaskEvents) == 0 {
		return nil
	}

	// Group events by task subject (more reliable than task_id from md5)
	type taskInfo struct {
		subject   string
		taskID    string
		startCost float64
		startTok  int64
		endCost   float64
		endTok    int64
		startTime time.Time
		endTime   time.Time
		status    string
		started   bool
	}

	tasks := make(map[string]*taskInfo)
	var order []string

	for _, evt := range a.session.TaskEvents {
		key := evt.TaskSubject
		t, exists := tasks[key]
		if !exists {
			t = &taskInfo{
				subject: evt.TaskSubject,
				taskID:  evt.TaskID,
				status:  "pending",
			}
			tasks[key] = t
			order = append(order, key)
		}

		switch evt.Event {
		case "task_started":
			if !t.started {
				t.startCost = evt.CostSnap
				t.startTok = evt.TokenSnap
				t.startTime = evt.Timestamp
				t.started = true
			}
			t.status = "running"
		case "task_completed":
			t.endCost = evt.CostSnap
			t.endTok = evt.TokenSnap
			t.endTime = evt.Timestamp
			t.status = "completed"
		case "task_updated":
			if evt.TaskStatus == "in_progress" && !t.started {
				t.startCost = evt.CostSnap
				t.startTok = evt.TokenSnap
				t.startTime = evt.Timestamp
				t.started = true
				t.status = "running"
			}
		}
	}

	// For running tasks, use the latest snapshot as "end"
	var latestCost float64
	var latestTok int64
	var latestTime time.Time
	if a.session.Latest != nil {
		latestCost = a.session.Latest.TotalCostUSD
		latestTok = a.session.Latest.TotalInputTok + a.session.Latest.TotalOutputTok
		latestTime = a.session.Latest.Timestamp
	}

	// Calculate total session cost for percentage
	totalCost := latestCost

	var result []model.TaskCost
	for _, key := range order {
		t := tasks[key]
		if !t.started {
			continue
		}

		endCost := t.endCost
		endTok := t.endTok
		endTime := t.endTime
		if t.status == "running" {
			endCost = latestCost
			endTok = latestTok
			endTime = latestTime
		}

		deltaCost := endCost - t.startCost
		deltaTok := endTok - t.startTok

		var pct float64
		if totalCost > 0 {
			pct = (deltaCost / totalCost) * 100
		}

		result = append(result, model.TaskCost{
			TaskID:      t.taskID,
			Subject:     t.subject,
			Status:      t.status,
			StartCost:   t.startCost,
			EndCost:     endCost,
			DeltaCost:   deltaCost,
			StartTokens: t.startTok,
			EndTokens:   endTok,
			DeltaTokens: deltaTok,
			StartTime:   t.startTime,
			EndTime:     endTime,
			Duration:    endTime.Sub(t.startTime),
			Percentage:  pct,
		})
	}

	return result
}

// Summary returns high-level metrics for the session.
func (a *Analyzer) Summary() model.SessionSummary {
	s := model.SessionSummary{
		SessionID: a.session.ID,
	}

	if a.session.Latest != nil {
		l := a.session.Latest
		s.TotalCost = l.TotalCostUSD
		s.InputTokens = l.TotalInputTok
		s.OutputTokens = l.TotalOutputTok
		s.TotalTokens = l.TotalInputTok + l.TotalOutputTok
		s.CacheReadTok = l.CacheReadTok
		s.CacheWriteTok = l.CacheWriteTok
		s.ContextUsedPct = l.ContextUsedPct
		s.LinesAdded = l.LinesAdded
		s.LinesRemoved = l.LinesRemoved
		s.Model = l.Model
		if l.DurationMS > 0 {
			s.Duration = time.Duration(l.DurationMS) * time.Millisecond
		}
	}

	// Count unique completed tasks
	completed := make(map[string]bool)
	for _, evt := range a.session.TaskEvents {
		if evt.Event == "task_completed" {
			completed[evt.TaskSubject] = true
		}
	}
	s.TaskCount = len(completed)

	if s.TaskCount > 0 {
		s.AvgCostPerTask = s.TotalCost / float64(s.TaskCount)
	}

	totalInput := s.InputTokens + s.CacheReadTok
	if totalInput > 0 {
		s.CacheHitRate = float64(s.CacheReadTok) / float64(totalInput) * 100
	}

	return s
}

// Tips generates optimization suggestions based on current session data.
func (a *Analyzer) Tips() []string {
	var tips []string
	summary := a.Summary()

	// Cache hit rate
	if summary.TotalTokens > 1000 {
		if summary.CacheHitRate < 30 {
			tips = append(tips, fmt.Sprintf("Low cache hit rate (%.0f%%). Consider structuring prompts to maximize cache reuse.", summary.CacheHitRate))
		} else if summary.CacheHitRate > 70 {
			tips = append(tips, fmt.Sprintf("Great cache hit rate (%.0f%%)! Your prompts are well-structured for caching.", summary.CacheHitRate))
		}
	}

	// Context window usage
	if summary.ContextUsedPct > 80 {
		tips = append(tips, fmt.Sprintf("Context window is %.0f%% full. Consider using /compact to free space.", summary.ContextUsedPct))
	} else if summary.ContextUsedPct > 60 {
		tips = append(tips, fmt.Sprintf("Context at %.0f%%. Keep an eye on it — heavy tool use fills context fast.", summary.ContextUsedPct))
	}

	// Expensive tasks
	taskCosts := a.TaskCosts()
	if len(taskCosts) > 1 {
		sort.Slice(taskCosts, func(i, j int) bool {
			return taskCosts[i].DeltaCost > taskCosts[j].DeltaCost
		})
		most := taskCosts[0]
		if most.DeltaCost > 0 && most.Percentage > 40 {
			tips = append(tips, fmt.Sprintf("\"%s\" used %.0f%% of total cost ($%.4f). Consider breaking it into smaller tasks.", most.Subject, most.Percentage, most.DeltaCost))
		}
	}

	// Output vs input ratio
	if summary.InputTokens > 0 {
		ratio := float64(summary.OutputTokens) / float64(summary.InputTokens)
		if ratio < 0.05 {
			tips = append(tips, "Very low output/input ratio — most cost is from reading context. Use targeted file reads instead of broad searches.")
		}
	}

	// Lines of code efficiency
	totalLines := summary.LinesAdded + summary.LinesRemoved
	if totalLines > 0 && summary.TotalCost > 0.1 {
		costPerLine := summary.TotalCost / float64(totalLines)
		if costPerLine > 0.01 {
			tips = append(tips, fmt.Sprintf("$%.4f per line of code changed. Consider using subagents to parallelize independent tasks.", costPerLine))
		}
	}

	if len(tips) == 0 {
		tips = append(tips, "Session looks efficient so far. Keep going!")
	}

	return tips
}
