#!/bin/bash
# Integration tests for claude-status hook scripts.
# Requires: jq, bash, bc
# Usage: bash cmd/claude-status/hooks/hooks_test.sh

set -euo pipefail

PASS=0
FAIL=0
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

pass() { PASS=$((PASS + 1)); echo "  PASS: $1"; }
fail() { FAIL=$((FAIL + 1)); echo "  FAIL: $1 — $2"; }

# ---------------------------------------------------------------------------
# status-line.sh tests
# ---------------------------------------------------------------------------
echo "=== status-line.sh ==="

MOCK_INPUT='{"session_id":"test-sess","cost":{"total_cost_usd":0.35,"total_duration_ms":600000,"total_api_duration_ms":120000,"total_lines_added":210,"total_lines_removed":15},"context_window":{"total_input_tokens":45000,"total_output_tokens":12000,"current_usage":{"input_tokens":10000,"output_tokens":12000,"cache_read_input_tokens":35000,"cache_creation_input_tokens":8000},"context_window_size":200000,"used_percentage":34},"model":{"display_name":"Claude Opus 4.6"}}'

# Test 1: script exits 0
OUTPUT=$(echo "$MOCK_INPUT" | CLAUDE_STATUS_DIR="$TMPDIR" bash "$SCRIPT_DIR/status-line.sh" 2>&1) && pass "exits 0" || fail "exits 0" "non-zero exit code"

# Test 2: JSONL file is created
JSONL="$TMPDIR/sessions/test-sess.jsonl"
if [ -f "$JSONL" ]; then
  pass "creates JSONL file"
else
  fail "creates JSONL file" "file not found"
fi

# Test 3: JSONL contains valid JSON
if jq empty "$JSONL" 2>/dev/null; then
  pass "JSONL is valid JSON"
else
  fail "JSONL is valid JSON" "malformed JSON"
fi

# Test 4: JSONL has correct fields
if jq -e '.type == "snapshot"' "$JSONL" >/dev/null 2>&1; then
  pass "snapshot type field"
else
  fail "snapshot type field" "missing or wrong type"
fi

if jq -e '.total_cost_usd == 0.35' "$JSONL" >/dev/null 2>&1; then
  pass "total_cost_usd field"
else
  fail "total_cost_usd field" "wrong value"
fi

if jq -e '.session_id == "test-sess"' "$JSONL" >/dev/null 2>&1; then
  pass "session_id field"
else
  fail "session_id field" "wrong value"
fi

if jq -e '.model == "Claude Opus 4.6"' "$JSONL" >/dev/null 2>&1; then
  pass "model field"
else
  fail "model field" "wrong value"
fi

# Test 5: output contains cost display
if echo "$OUTPUT" | grep -q '\$0.3500'; then
  pass "output shows cost"
else
  fail "output shows cost" "cost not found in output"
fi

# Test 6: output contains token count
if echo "$OUTPUT" | grep -q 'tokens'; then
  pass "output shows tokens"
else
  fail "output shows tokens" "tokens not found in output"
fi

# Test 7: multiple snapshots append (not overwrite)
echo "$MOCK_INPUT" | CLAUDE_STATUS_DIR="$TMPDIR" bash "$SCRIPT_DIR/status-line.sh" >/dev/null 2>&1
LINE_COUNT=$(wc -l < "$JSONL" | tr -d ' ')
if [ "$LINE_COUNT" -eq 2 ]; then
  pass "appends snapshots ($LINE_COUNT lines)"
else
  fail "appends snapshots" "expected 2 lines, got $LINE_COUNT"
fi

# Test 8: Sonnet model detection
SONNET_INPUT=$(echo "$MOCK_INPUT" | jq '.model.display_name = "Claude Sonnet 4.6"')
SONNET_OUT=$(echo "$SONNET_INPUT" | CLAUDE_STATUS_DIR="$TMPDIR/sonnet" bash "$SCRIPT_DIR/status-line.sh" 2>&1) && pass "Sonnet model exits 0" || fail "Sonnet model exits 0" "non-zero"

# Test 9: Haiku model detection
HAIKU_INPUT=$(echo "$MOCK_INPUT" | jq '.model.display_name = "Claude Haiku 4.5"')
HAIKU_OUT=$(echo "$HAIKU_INPUT" | CLAUDE_STATUS_DIR="$TMPDIR/haiku" bash "$SCRIPT_DIR/status-line.sh" 2>&1) && pass "Haiku model exits 0" || fail "Haiku model exits 0" "non-zero"

# Test 10: zero-duration input (no burn rate division by zero)
ZERO_DUR=$(echo "$MOCK_INPUT" | jq '.cost.total_duration_ms = 0')
echo "$ZERO_DUR" | CLAUDE_STATUS_DIR="$TMPDIR/zerodur" bash "$SCRIPT_DIR/status-line.sh" >/dev/null 2>&1 && pass "zero duration no crash" || fail "zero duration no crash" "crash on zero duration"

# ---------------------------------------------------------------------------
# task-hook.sh tests
# ---------------------------------------------------------------------------
echo ""
echo "=== task-hook.sh ==="

TASK_DIR="$TMPDIR/task-test"
mkdir -p "$TASK_DIR/sessions"

# Seed a snapshot so the task hook can read cost data
echo '{"type":"snapshot","timestamp":"2026-03-26T15:00:00Z","session_id":"task-sess","total_cost_usd":0.05,"total_input_tokens":8000,"total_output_tokens":2000,"cache_read_tokens":3000,"cache_write_tokens":1500,"context_used_pct":12,"context_window_size":200000,"total_duration_ms":30000,"total_api_duration_ms":5000,"total_lines_added":10,"total_lines_removed":2,"model":"Opus"}' > "$TASK_DIR/sessions/task-sess.jsonl"

TASK_INPUT='{"session_id":"task-sess","hook_event_name":"PostToolUse","tool_name":"TodoWrite","tool_input":{"todos":[{"content":"Setup project","status":"in_progress"},{"content":"Write tests","status":"pending"}]}}'

# Test 1: exits 0
TASK_OUT=$(echo "$TASK_INPUT" | CLAUDE_STATUS_DIR="$TASK_DIR" bash "$SCRIPT_DIR/task-hook.sh" 2>&1) && pass "exits 0" || fail "exits 0" "non-zero exit"

# Test 2: emits task_started event
TASK_JSONL="$TASK_DIR/sessions/task-sess.jsonl"
if grep -q '"event":"task_started"' "$TASK_JSONL"; then
  pass "emits task_started"
else
  fail "emits task_started" "no task_started event"
fi

# Test 3: task_started has correct subject
if grep '"event":"task_started"' "$TASK_JSONL" | jq -e '.task_subject == "Setup project"' >/dev/null 2>&1; then
  pass "task_started subject correct"
else
  fail "task_started subject correct" "wrong subject"
fi

# Test 4: task_started has cost snapshot
if grep '"event":"task_started"' "$TASK_JSONL" | jq -e '.cost_snapshot_usd == 0.05' >/dev/null 2>&1; then
  pass "cost snapshot in task event"
else
  fail "cost snapshot in task event" "wrong cost snapshot"
fi

# Test 5: completing a task
COMPLETE_INPUT='{"session_id":"task-sess","hook_event_name":"PostToolUse","tool_name":"TodoWrite","tool_input":{"todos":[{"content":"Setup project","status":"completed"},{"content":"Write tests","status":"in_progress"}]}}'
echo "$COMPLETE_INPUT" | CLAUDE_STATUS_DIR="$TASK_DIR" bash "$SCRIPT_DIR/task-hook.sh" >/dev/null 2>&1

if grep -q '"event":"task_completed"' "$TASK_JSONL"; then
  pass "emits task_completed"
else
  fail "emits task_completed" "no task_completed event"
fi

if grep -q '"event":"task_started".*"Write tests"' "$TASK_JSONL"; then
  pass "second task started"
else
  fail "second task started" "Write tests not started"
fi

# Test 6: output is valid JSON (should be {})
if echo "$TASK_OUT" | jq empty 2>/dev/null; then
  pass "output is valid JSON"
else
  fail "output is valid JSON" "invalid output: $TASK_OUT"
fi

# Test 7: non-TodoWrite tool is ignored
OTHER_INPUT='{"session_id":"task-sess","hook_event_name":"PostToolUse","tool_name":"Read","tool_input":{}}'
BEFORE_LINES=$(wc -l < "$TASK_JSONL" | tr -d ' ')
echo "$OTHER_INPUT" | CLAUDE_STATUS_DIR="$TASK_DIR" bash "$SCRIPT_DIR/task-hook.sh" >/dev/null 2>&1
AFTER_LINES=$(wc -l < "$TASK_JSONL" | tr -d ' ')
if [ "$BEFORE_LINES" -eq "$AFTER_LINES" ]; then
  pass "ignores non-TodoWrite tools"
else
  fail "ignores non-TodoWrite tools" "lines changed from $BEFORE_LINES to $AFTER_LINES"
fi

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
echo ""
echo "=== Results: $PASS passed, $FAIL failed ==="
if [ "$FAIL" -gt 0 ]; then
  exit 1
fi
