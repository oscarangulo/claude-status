package model

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func TestParseSessionFile(t *testing.T) {
	dir := t.TempDir()
	path := filepath.Join(dir, "test-session.jsonl")

	content := `{"type":"snapshot","timestamp":"2026-03-26T15:00:00Z","session_id":"sess-1","total_cost_usd":0.05,"total_input_tokens":8000,"total_output_tokens":2000,"cache_read_tokens":3000,"cache_write_tokens":1500,"context_used_pct":12,"context_window_size":1000000,"total_duration_ms":30000,"total_api_duration_ms":5000,"total_lines_added":10,"total_lines_removed":2,"model":"Opus"}
{"type":"task_event","timestamp":"2026-03-26T15:00:01Z","session_id":"sess-1","event":"task_started","task_id":"t1","task_subject":"Setup project","task_status":"in_progress","cost_snapshot_usd":0.05,"token_snapshot":10000}
{"type":"snapshot","timestamp":"2026-03-26T15:01:00Z","session_id":"sess-1","total_cost_usd":0.12,"total_input_tokens":20000,"total_output_tokens":5000,"cache_read_tokens":8000,"cache_write_tokens":3000,"context_used_pct":18,"context_window_size":1000000,"total_duration_ms":90000,"total_api_duration_ms":12000,"total_lines_added":45,"total_lines_removed":0,"model":"Opus"}
{"type":"task_event","timestamp":"2026-03-26T15:01:01Z","session_id":"sess-1","event":"task_completed","task_id":"t1","task_subject":"Setup project","task_status":"completed","cost_snapshot_usd":0.12,"token_snapshot":25000}
`
	os.WriteFile(path, []byte(content), 0644)

	session, err := ParseSessionFile(path)
	if err != nil {
		t.Fatalf("ParseSessionFile error: %v", err)
	}

	if session.ID != "sess-1" {
		t.Errorf("expected session ID 'sess-1', got '%s'", session.ID)
	}
	if len(session.Snapshots) != 2 {
		t.Errorf("expected 2 snapshots, got %d", len(session.Snapshots))
	}
	if len(session.TaskEvents) != 2 {
		t.Errorf("expected 2 task events, got %d", len(session.TaskEvents))
	}
	if session.Latest == nil {
		t.Fatal("expected Latest snapshot to be set")
	}
	if session.Latest.TotalCostUSD != 0.12 {
		t.Errorf("expected latest cost 0.12, got %f", session.Latest.TotalCostUSD)
	}
	if session.Latest.Model != "Opus" {
		t.Errorf("expected model 'Opus', got '%s'", session.Latest.Model)
	}
}

func TestParseSessionFile_MalformedLines(t *testing.T) {
	dir := t.TempDir()
	path := filepath.Join(dir, "bad.jsonl")

	content := `not json at all
{"type":"snapshot","timestamp":"2026-03-26T15:00:00Z","session_id":"s1","total_cost_usd":0.01,"total_input_tokens":100,"total_output_tokens":50,"cache_read_tokens":0,"cache_write_tokens":0,"context_used_pct":1,"context_window_size":1000000,"total_duration_ms":1000,"total_api_duration_ms":500,"total_lines_added":0,"total_lines_removed":0,"model":"Opus"}
{"broken json
`
	os.WriteFile(path, []byte(content), 0644)

	session, err := ParseSessionFile(path)
	if err != nil {
		t.Fatalf("expected no error for malformed lines, got: %v", err)
	}
	if len(session.Snapshots) != 1 {
		t.Errorf("expected 1 valid snapshot, got %d", len(session.Snapshots))
	}
}

func TestParseSessionFile_Empty(t *testing.T) {
	dir := t.TempDir()
	path := filepath.Join(dir, "empty.jsonl")
	os.WriteFile(path, []byte(""), 0644)

	session, err := ParseSessionFile(path)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if len(session.Snapshots) != 0 {
		t.Errorf("expected 0 snapshots, got %d", len(session.Snapshots))
	}
}

func TestParseNewLines(t *testing.T) {
	content := `{"type":"snapshot","timestamp":"2026-03-26T15:00:00Z","session_id":"s1","total_cost_usd":0.01,"total_input_tokens":100,"total_output_tokens":50,"cache_read_tokens":0,"cache_write_tokens":0,"context_used_pct":1,"context_window_size":1000000,"total_duration_ms":1000,"total_api_duration_ms":500,"total_lines_added":0,"total_lines_removed":0,"model":"Opus"}
{"type":"task_event","timestamp":"2026-03-26T15:00:01Z","session_id":"s1","event":"task_started","task_id":"t1","task_subject":"Test","task_status":"in_progress","cost_snapshot_usd":0.01,"token_snapshot":150}
`
	r := strings.NewReader(content)

	snaps, events, offset, err := ParseNewLines(r, 0)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if len(snaps) != 1 {
		t.Errorf("expected 1 snapshot, got %d", len(snaps))
	}
	if len(events) != 1 {
		t.Errorf("expected 1 event, got %d", len(events))
	}
	if offset == 0 {
		t.Error("expected offset > 0")
	}

	// Read again from offset — should get nothing
	r = strings.NewReader(content)
	snaps2, events2, _, err := ParseNewLines(r, offset)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if len(snaps2) != 0 || len(events2) != 0 {
		t.Error("expected no new entries when reading from end offset")
	}
}
