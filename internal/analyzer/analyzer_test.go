package analyzer

import (
	"testing"
	"time"

	"github.com/oscarangulo/claude-status/internal/model"
)

func TestTaskCosts(t *testing.T) {
	a := New()

	t0 := time.Date(2026, 3, 26, 15, 0, 0, 0, time.UTC)
	t1 := time.Date(2026, 3, 26, 15, 1, 0, 0, time.UTC)
	t2 := time.Date(2026, 3, 26, 15, 2, 0, 0, time.UTC)
	t3 := time.Date(2026, 3, 26, 15, 3, 0, 0, time.UTC)

	a.AddSnapshot(model.Snapshot{Timestamp: t0, SessionID: "s1", TotalCostUSD: 0.02, TotalInputTok: 5000, TotalOutputTok: 1000})
	a.AddTaskEvent(model.TaskEvent{Timestamp: t0, SessionID: "s1", Event: "task_started", TaskID: "t1", TaskSubject: "Setup", CostSnap: 0.02, TokenSnap: 6000})
	a.AddSnapshot(model.Snapshot{Timestamp: t1, SessionID: "s1", TotalCostUSD: 0.08, TotalInputTok: 20000, TotalOutputTok: 5000})
	a.AddTaskEvent(model.TaskEvent{Timestamp: t1, SessionID: "s1", Event: "task_completed", TaskID: "t1", TaskSubject: "Setup", CostSnap: 0.08, TokenSnap: 25000})
	a.AddTaskEvent(model.TaskEvent{Timestamp: t2, SessionID: "s1", Event: "task_started", TaskID: "t2", TaskSubject: "Auth", CostSnap: 0.08, TokenSnap: 25000})
	a.AddSnapshot(model.Snapshot{Timestamp: t3, SessionID: "s1", TotalCostUSD: 0.20, TotalInputTok: 50000, TotalOutputTok: 12000})

	costs := a.TaskCosts()
	if len(costs) != 2 {
		t.Fatalf("expected 2 task costs, got %d", len(costs))
	}

	// Task 1: Setup (completed)
	if costs[0].Subject != "Setup" {
		t.Errorf("expected 'Setup', got '%s'", costs[0].Subject)
	}
	if costs[0].Status != "completed" {
		t.Errorf("expected 'completed', got '%s'", costs[0].Status)
	}
	if !approx(costs[0].DeltaCost, 0.06) {
		t.Errorf("expected delta cost ~0.06, got %f", costs[0].DeltaCost)
	}

	// Task 2: Auth (running)
	if costs[1].Subject != "Auth" {
		t.Errorf("expected 'Auth', got '%s'", costs[1].Subject)
	}
	if costs[1].Status != "running" {
		t.Errorf("expected 'running', got '%s'", costs[1].Status)
	}
	if !approx(costs[1].DeltaCost, 0.12) {
		t.Errorf("expected delta cost ~0.12, got %f", costs[1].DeltaCost)
	}
}

func TestTaskCosts_UsesTaskIDForRepeatedSubjects(t *testing.T) {
	a := New()

	t0 := time.Date(2026, 3, 26, 15, 0, 0, 0, time.UTC)
	t1 := time.Date(2026, 3, 26, 15, 1, 0, 0, time.UTC)
	t2 := time.Date(2026, 3, 26, 15, 2, 0, 0, time.UTC)
	t3 := time.Date(2026, 3, 26, 15, 3, 0, 0, time.UTC)

	a.AddSnapshot(model.Snapshot{Timestamp: t0, SessionID: "s1", TotalCostUSD: 0.01, TotalInputTok: 1000, TotalOutputTok: 500})
	a.AddTaskEvent(model.TaskEvent{Timestamp: t0, SessionID: "s1", Event: "task_started", TaskID: "task-a-1", TaskSubject: "Write tests", CostSnap: 0.01, TokenSnap: 1500})
	a.AddSnapshot(model.Snapshot{Timestamp: t1, SessionID: "s1", TotalCostUSD: 0.03, TotalInputTok: 3000, TotalOutputTok: 1000})
	a.AddTaskEvent(model.TaskEvent{Timestamp: t1, SessionID: "s1", Event: "task_completed", TaskID: "task-a-1", TaskSubject: "Write tests", CostSnap: 0.03, TokenSnap: 4000})
	a.AddTaskEvent(model.TaskEvent{Timestamp: t2, SessionID: "s1", Event: "task_started", TaskID: "task-a-2", TaskSubject: "Write tests", CostSnap: 0.03, TokenSnap: 4000})
	a.AddSnapshot(model.Snapshot{Timestamp: t3, SessionID: "s1", TotalCostUSD: 0.08, TotalInputTok: 8000, TotalOutputTok: 2000})
	a.AddTaskEvent(model.TaskEvent{Timestamp: t3, SessionID: "s1", Event: "task_completed", TaskID: "task-a-2", TaskSubject: "Write tests", CostSnap: 0.08, TokenSnap: 10000})

	costs := a.TaskCosts()
	if len(costs) != 2 {
		t.Fatalf("expected 2 distinct tasks, got %d", len(costs))
	}
	if !approx(costs[0].DeltaCost, 0.02) {
		t.Fatalf("expected first delta ~0.02, got %f", costs[0].DeltaCost)
	}
	if !approx(costs[1].DeltaCost, 0.05) {
		t.Fatalf("expected second delta ~0.05, got %f", costs[1].DeltaCost)
	}
}

func TestSummary(t *testing.T) {
	a := New()

	a.AddSnapshot(model.Snapshot{
		SessionID:      "s1",
		TotalCostUSD:   0.50,
		TotalInputTok:  100000,
		TotalOutputTok: 25000,
		CacheReadTok:   40000,
		CacheWriteTok:  10000,
		ContextUsedPct: 45,
		LinesAdded:     200,
		LinesRemoved:   30,
		DurationMS:     300000,
		Model:          "Claude Opus 4.6",
	})
	a.AddTaskEvent(model.TaskEvent{Event: "task_completed", TaskSubject: "Task A"})
	a.AddTaskEvent(model.TaskEvent{Event: "task_completed", TaskSubject: "Task B"})

	s := a.Summary()

	if s.TotalCost != 0.50 {
		t.Errorf("expected cost 0.50, got %f", s.TotalCost)
	}
	if s.TotalTokens != 125000 {
		t.Errorf("expected 125000 tokens, got %d", s.TotalTokens)
	}
	if s.TaskCount != 2 {
		t.Errorf("expected 2 tasks, got %d", s.TaskCount)
	}
	if s.AvgCostPerTask != 0.25 {
		t.Errorf("expected avg cost 0.25, got %f", s.AvgCostPerTask)
	}
	// Cache hit rate: 40000 / (100000 + 40000) ~= 28.57%
	if s.CacheHitRate < 28 || s.CacheHitRate > 29 {
		t.Errorf("expected cache hit rate ~28.57%%, got %f", s.CacheHitRate)
	}
	if s.Model != "Claude Opus 4.6" {
		t.Errorf("expected 'Claude Opus 4.6', got '%s'", s.Model)
	}
}

func TestTips(t *testing.T) {
	a := New()

	// Low cache scenario
	a.AddSnapshot(model.Snapshot{
		TotalCostUSD:   0.30,
		TotalInputTok:  50000,
		TotalOutputTok: 10000,
		CacheReadTok:   2000,
		CacheWriteTok:  20000,
		ContextUsedPct: 85,
	})

	tips := a.Tips()
	if len(tips) == 0 {
		t.Fatal("expected at least one tip")
	}

	// Should have low cache warning and high context warning
	hasCache := false
	hasContext := false
	for _, tip := range tips {
		if contains(tip, "cache") || contains(tip, "Cache") {
			hasCache = true
		}
		if contains(tip, "Context") || contains(tip, "context") || contains(tip, "compact") {
			hasContext = true
		}
	}
	if !hasCache {
		t.Error("expected a cache-related tip")
	}
	if !hasContext {
		t.Error("expected a context-related tip")
	}
}

func approx(a, b float64) bool {
	diff := a - b
	if diff < 0 {
		diff = -diff
	}
	return diff < 0.001
}

func contains(s, substr string) bool {
	return len(s) >= len(substr) && stringContains(s, substr)
}

func stringContains(s, sub string) bool {
	for i := 0; i <= len(s)-len(sub); i++ {
		if s[i:i+len(sub)] == sub {
			return true
		}
	}
	return false
}
