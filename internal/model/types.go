package model

import "time"

// Snapshot represents a point-in-time capture of token usage and cost from the status line.
type Snapshot struct {
	Timestamp      time.Time `json:"timestamp"`
	SessionID      string    `json:"session_id"`
	Type           string    `json:"type"` // "snapshot"
	TotalCostUSD   float64   `json:"total_cost_usd"`
	TotalInputTok  int64     `json:"total_input_tokens"`
	TotalOutputTok int64     `json:"total_output_tokens"`
	CacheReadTok   int64     `json:"cache_read_tokens"`
	CacheWriteTok  int64     `json:"cache_write_tokens"`
	ContextUsedPct float64   `json:"context_used_pct"`
	ContextSize    int64     `json:"context_window_size"`
	DurationMS     int64     `json:"total_duration_ms"`
	APIDurationMS  int64     `json:"total_api_duration_ms"`
	LinesAdded     int64     `json:"total_lines_added"`
	LinesRemoved   int64     `json:"total_lines_removed"`
	Model          string    `json:"model"`
}

// TaskEvent represents a task state change captured by hooks.
type TaskEvent struct {
	Timestamp   time.Time `json:"timestamp"`
	SessionID   string    `json:"session_id"`
	Type        string    `json:"type"` // "task_event"
	Event       string    `json:"event"`
	TaskID      string    `json:"task_id"`
	TaskSubject string    `json:"task_subject"`
	TaskStatus  string    `json:"task_status"`
	CostSnap    float64   `json:"cost_snapshot_usd"`
	TokenSnap   int64     `json:"token_snapshot"`
}

// TaskCost holds the computed cost breakdown for a single plan task.
type TaskCost struct {
	TaskID      string
	Subject     string
	Status      string // "running", "completed"
	StartCost   float64
	EndCost     float64
	DeltaCost   float64
	StartTokens int64
	EndTokens   int64
	DeltaTokens int64
	StartTime   time.Time
	EndTime     time.Time
	Duration    time.Duration
	Percentage  float64 // percentage of total session cost
}

// SubagentEvent records the cost of a single subagent execution.
type SubagentEvent struct {
	Timestamp   time.Time `json:"timestamp"`
	SessionID   string    `json:"session_id"`
	Type        string    `json:"type"` // "subagent_event"
	AgentID     string    `json:"agent_id"`
	AgentType   string    `json:"agent_type"`
	CostUSD     float64   `json:"cost_usd"`
	InputTokens int64     `json:"input_tokens"`
	OutputTokens int64    `json:"output_tokens"`
	Model       string    `json:"model"`
}

// Session aggregates all data for a single Claude Code session.
type Session struct {
	ID             string
	StartedAt      time.Time
	Snapshots      []Snapshot
	TaskEvents     []TaskEvent
	SubagentEvents []SubagentEvent
	Latest         *Snapshot
}

// SessionSummary provides high-level metrics for a session.
type SessionSummary struct {
	SessionID      string
	TotalCost      float64
	TotalTokens    int64
	InputTokens    int64
	OutputTokens   int64
	CacheReadTok   int64
	CacheWriteTok  int64
	ContextUsedPct float64
	Duration       time.Duration
	TaskCount      int
	AvgCostPerTask float64
	CacheHitRate   float64
	LinesAdded     int64
	LinesRemoved   int64
	Model          string
}
