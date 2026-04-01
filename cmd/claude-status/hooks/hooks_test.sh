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
# task-hook.sh — plan estimate tests
# ---------------------------------------------------------------------------
echo ""
echo "=== task-hook.sh — plan estimate ==="

EST_DIR="$TMPDIR/est-test"
mkdir -p "$EST_DIR/sessions"

# Seed historical completed tasks in a past session (need 2+ for avg)
cat > "$EST_DIR/sessions/past-sess.jsonl" <<'HIST'
{"type":"snapshot","timestamp":"2026-03-25T15:00:00Z","session_id":"past-sess","total_cost_usd":5.00}
{"type":"task_event","timestamp":"2026-03-25T15:01:00Z","session_id":"past-sess","event":"task_started","task_id":"t1","task_key":"task-aaa","task_subject":"Task A","task_status":"in_progress","cost_snapshot_usd":1.00,"token_snapshot":1000}
{"type":"task_event","timestamp":"2026-03-25T15:10:00Z","session_id":"past-sess","event":"task_completed","task_id":"t1","task_key":"task-aaa","task_subject":"Task A","task_status":"completed","cost_snapshot_usd":3.00,"token_snapshot":3000}
{"type":"task_event","timestamp":"2026-03-25T15:11:00Z","session_id":"past-sess","event":"task_started","task_id":"t2","task_key":"task-bbb","task_subject":"Task B","task_status":"in_progress","cost_snapshot_usd":3.00,"token_snapshot":3000}
{"type":"task_event","timestamp":"2026-03-25T15:20:00Z","session_id":"past-sess","event":"task_completed","task_id":"t2","task_key":"task-bbb","task_subject":"Task B","task_status":"completed","cost_snapshot_usd":5.00,"token_snapshot":5000}
HIST
# Task A cost $2.00, Task B cost $2.00 → avg = $2.00

# Seed a snapshot for the current session
echo '{"type":"snapshot","timestamp":"2026-03-26T15:00:00Z","session_id":"est-sess","total_cost_usd":0.10}' > "$EST_DIR/sessions/est-sess.jsonl"

# Create a new plan with 4 tasks
EST_PLAN='{"session_id":"est-sess","hook_event_name":"PostToolUse","tool_name":"TodoWrite","tool_input":{"todos":[{"content":"Implement auth","status":"pending"},{"content":"Add tests","status":"pending"},{"content":"Write docs","status":"pending"},{"content":"Deploy","status":"pending"}]}}'

EST_OUT=$(echo "$EST_PLAN" | CLAUDE_STATUS_DIR="$EST_DIR" bash "$SCRIPT_DIR/task-hook.sh" 2>&1)

# Test 1: plan estimate appears in output
if echo "$EST_OUT" | grep -q "Plan estimate"; then
  pass "plan estimate in output"
else
  fail "plan estimate in output" "output: $EST_OUT"
fi

# Test 2: output contains task count
if echo "$EST_OUT" | grep -q "4 tasks"; then
  pass "plan estimate has task count"
else
  fail "plan estimate has task count" "output: $EST_OUT"
fi

# Test 3: output is valid JSON with additionalContext
if echo "$EST_OUT" | jq -e '.hookSpecificOutput.additionalContext' >/dev/null 2>&1; then
  pass "plan estimate uses additionalContext"
else
  fail "plan estimate uses additionalContext" "output: $EST_OUT"
fi

# Test 4: plan with budget — seed budget and check remaining message
echo '{"daily_limit":10.00}' > "$EST_DIR/budget.json"
EST_OUT2=$(echo "$EST_PLAN" | CLAUDE_STATUS_DIR="$EST_DIR" bash "$SCRIPT_DIR/task-hook.sh" 2>&1)
if echo "$EST_OUT2" | grep -q "budget\|Budget\|remaining\|limit"; then
  pass "plan estimate includes budget info"
else
  fail "plan estimate includes budget info" "output: $EST_OUT2"
fi

# Test 5: small update (< 3 new tasks) should NOT trigger estimate
SMALL_UPDATE='{"session_id":"est-sess","hook_event_name":"PostToolUse","tool_name":"TodoWrite","tool_input":{"todos":[{"content":"Implement auth","status":"in_progress"},{"content":"Add tests","status":"pending"}]}}'
SMALL_OUT=$(echo "$SMALL_UPDATE" | CLAUDE_STATUS_DIR="$EST_DIR" bash "$SCRIPT_DIR/task-hook.sh" 2>&1)
if echo "$SMALL_OUT" | grep -q "Plan estimate"; then
  fail "no estimate on small update" "estimate fired for < 3 tasks"
else
  pass "no estimate on small update"
fi

# ---------------------------------------------------------------------------
# snapshot-hook.sh tests
# ---------------------------------------------------------------------------
echo ""
echo "=== snapshot-hook.sh ==="

SNAP_DIR="$TMPDIR/snap-test"
mkdir -p "$SNAP_DIR/sessions"

# Create a mock native Claude Code session structure
NATIVE_DIR="$TMPDIR/.claude/projects/-test-project"
mkdir -p "$NATIVE_DIR"
cat > "$NATIVE_DIR/snap-sess.jsonl" <<'NATIVE'
{"type":"user","message":{"role":"user","content":"hello"},"timestamp":"2026-03-26T15:00:00.000Z","sessionId":"snap-sess"}
{"type":"assistant","message":{"role":"assistant","model":"claude-opus-4-6","usage":{"input_tokens":100,"output_tokens":50,"cache_read_input_tokens":500,"cache_creation_input_tokens":200}},"timestamp":"2026-03-26T15:00:05.000Z","sessionId":"snap-sess"}
{"type":"user","message":{"role":"user","content":"do more"},"timestamp":"2026-03-26T15:01:00.000Z","sessionId":"snap-sess"}
{"type":"assistant","message":{"role":"assistant","model":"claude-opus-4-6","usage":{"input_tokens":150,"output_tokens":80,"cache_read_input_tokens":600,"cache_creation_input_tokens":100}},"timestamp":"2026-03-26T15:01:10.000Z","sessionId":"snap-sess"}
NATIVE

SNAP_INPUT='{"session_id":"snap-sess","hook_event_name":"PostToolUse","tool_name":"Bash","tool_input":{}}'

# Override HOME so find looks in the right place
SNAP_OUT=$(echo "$SNAP_INPUT" | HOME="$TMPDIR" CLAUDE_STATUS_DIR="$SNAP_DIR" bash "$SCRIPT_DIR/snapshot-hook.sh" 2>&1) && pass "exits 0" || fail "exits 0" "non-zero exit"

SNAP_JSONL="$SNAP_DIR/sessions/snap-sess.jsonl"

# Test 1: snapshot was written
if [ -f "$SNAP_JSONL" ] && grep -q '"type":"snapshot"' "$SNAP_JSONL"; then
  pass "writes snapshot"
else
  fail "writes snapshot" "no snapshot in file"
fi

# Test 2: snapshot has correct fields
if grep '"type":"snapshot"' "$SNAP_JSONL" | jq -e '.total_cost_usd > 0' >/dev/null 2>&1; then
  pass "cost is computed"
else
  fail "cost is computed" "cost is 0 or missing"
fi

if grep '"type":"snapshot"' "$SNAP_JSONL" | jq -e '.model == "claude-opus-4-6"' >/dev/null 2>&1; then
  pass "model detected"
else
  fail "model detected" "wrong model"
fi

if grep '"type":"snapshot"' "$SNAP_JSONL" | jq -e '.cache_read_tokens == 1100' >/dev/null 2>&1; then
  pass "cache_read aggregated (500+600=1100)"
else
  fail "cache_read aggregated" "wrong value"
fi

if grep '"type":"snapshot"' "$SNAP_JSONL" | jq -e '.total_duration_ms > 0' >/dev/null 2>&1; then
  pass "duration computed"
else
  fail "duration computed" "duration is 0"
fi

# Test 3: duplicate suppression (same cost = no new snapshot)
echo "$SNAP_INPUT" | HOME="$TMPDIR" CLAUDE_STATUS_DIR="$SNAP_DIR" bash "$SCRIPT_DIR/snapshot-hook.sh" >/dev/null 2>&1
SNAP_COUNT=$(grep -c '"type":"snapshot"' "$SNAP_JSONL")
if [ "$SNAP_COUNT" -eq 1 ]; then
  pass "deduplicates snapshots"
else
  fail "deduplicates snapshots" "expected 1 snapshot, got $SNAP_COUNT"
fi

# Test 4: missing native file gracefully returns {}
MISSING_OUT=$(echo '{"session_id":"nonexistent","hook_event_name":"PostToolUse","tool_name":"Bash","tool_input":{}}' | HOME="$TMPDIR" CLAUDE_STATUS_DIR="$SNAP_DIR" bash "$SCRIPT_DIR/snapshot-hook.sh" 2>&1)
if [ "$MISSING_OUT" = "{}" ]; then
  pass "graceful on missing session"
else
  fail "graceful on missing session" "output: $MISSING_OUT"
fi

# Test 5: output is always {}
if [ "$SNAP_OUT" = "{}" ]; then
  pass "output is {}"
else
  fail "output is {}" "output: $SNAP_OUT"
fi

# ---------------------------------------------------------------------------
# snapshot-hook.sh — cost pulse tests
# ---------------------------------------------------------------------------
echo ""
echo "=== snapshot-hook.sh — cost pulse ==="

PULSE_DIR="$TMPDIR/pulse-test"
mkdir -p "$PULSE_DIR/sessions"

# Create native session
PULSE_NATIVE="$TMPDIR/.claude/projects/-test-project/pulse-sess.jsonl"
cat > "$PULSE_NATIVE" <<'NATIVE'
{"type":"user","message":{"role":"user","content":"hello"},"timestamp":"2026-03-26T15:00:00.000Z","sessionId":"pulse-sess"}
{"type":"assistant","message":{"role":"assistant","model":"claude-opus-4-6","usage":{"input_tokens":5000,"output_tokens":1000,"cache_read_input_tokens":500,"cache_creation_input_tokens":200}},"timestamp":"2026-03-26T15:01:00.000Z","sessionId":"pulse-sess"}
NATIVE

# Seed pulse counter at 2 so next run is call #3 (triggers pulse)
echo "2" > "$PULSE_DIR/pulse-pulse-sess"

PULSE_OUT=$(echo '{"session_id":"pulse-sess","hook_event_name":"PostToolUse","tool_name":"Bash"}' | HOME="$TMPDIR" CLAUDE_STATUS_DIR="$PULSE_DIR" bash "$SCRIPT_DIR/snapshot-hook.sh" 2>&1)

if echo "$PULSE_OUT" | grep -q "Session:"; then
  pass "cost pulse fires on 3rd snapshot"
else
  fail "cost pulse fires on 3rd snapshot" "output: $PULSE_OUT"
fi

if echo "$PULSE_OUT" | grep -q "context"; then
  pass "cost pulse includes context %"
else
  fail "cost pulse includes context %" "output: $PULSE_OUT"
fi

# Test: pulse does NOT fire on 4th snapshot (not multiple of 3)
PULSE_OUT2=$(echo '{"session_id":"pulse-sess","hook_event_name":"PostToolUse","tool_name":"Bash"}' | HOME="$TMPDIR" CLAUDE_STATUS_DIR="$PULSE_DIR" bash "$SCRIPT_DIR/snapshot-hook.sh" 2>&1)
if [ "$PULSE_OUT2" = "{}" ]; then
  pass "no pulse on non-multiple snapshot"
else
  fail "no pulse on non-multiple snapshot" "output: $PULSE_OUT2"
fi

# ---------------------------------------------------------------------------
# snapshot-hook.sh — loop detection tests
# ---------------------------------------------------------------------------
echo ""
echo "=== snapshot-hook.sh — loop detection ==="

LOOP_DIR="$TMPDIR/loop-test"
mkdir -p "$LOOP_DIR/sessions"

# Create native session for loop test
LOOP_NATIVE="$TMPDIR/.claude/projects/-test-project/loop-sess.jsonl"
cat > "$LOOP_NATIVE" <<'NATIVE'
{"type":"user","message":{"role":"user","content":"hello"},"timestamp":"2026-03-26T15:00:00.000Z","sessionId":"loop-sess"}
{"type":"assistant","message":{"role":"assistant","model":"claude-opus-4-6","usage":{"input_tokens":100,"output_tokens":50,"cache_read_input_tokens":500,"cache_creation_input_tokens":200}},"timestamp":"2026-03-26T15:00:05.000Z","sessionId":"loop-sess"}
NATIVE

LOOP_BASE='{"session_id":"loop-sess","hook_event_name":"PostToolUse","tool_name":"Bash","tool_result":{"is_error":true}}'

# 1st and 2nd failures — no alert yet
echo "$LOOP_BASE" | HOME="$TMPDIR" CLAUDE_STATUS_DIR="$LOOP_DIR" bash "$SCRIPT_DIR/snapshot-hook.sh" >/dev/null 2>&1
LOOP_OUT2=$(echo "$LOOP_BASE" | HOME="$TMPDIR" CLAUDE_STATUS_DIR="$LOOP_DIR" bash "$SCRIPT_DIR/snapshot-hook.sh" 2>&1)
if echo "$LOOP_OUT2" | grep -q "Loop detected"; then
  fail "no alert before 3 failures" "alert fired too early"
else
  pass "no alert before 3 failures"
fi

# 3rd failure — should alert
LOOP_OUT3=$(echo "$LOOP_BASE" | HOME="$TMPDIR" CLAUDE_STATUS_DIR="$LOOP_DIR" bash "$SCRIPT_DIR/snapshot-hook.sh" 2>&1)
if echo "$LOOP_OUT3" | grep -q "Loop detected"; then
  pass "loop alert after 3 failures"
else
  fail "loop alert after 3 failures" "no alert on 3rd failure"
fi

# Success resets counter
SUCCESS_INPUT='{"session_id":"loop-sess","hook_event_name":"PostToolUse","tool_name":"Bash","tool_result":{"is_error":false}}'
echo "$SUCCESS_INPUT" | HOME="$TMPDIR" CLAUDE_STATUS_DIR="$LOOP_DIR" bash "$SCRIPT_DIR/snapshot-hook.sh" >/dev/null 2>&1
if [ ! -f "$LOOP_DIR/loop-loop-sess.json" ]; then
  pass "success resets loop counter"
else
  fail "success resets loop counter" "loop file still exists"
fi

# ---------------------------------------------------------------------------
# snapshot-hook.sh — session cost comparison tests
# ---------------------------------------------------------------------------
echo ""
echo "=== snapshot-hook.sh — session cost comparison ==="

COMP_DIR="$TMPDIR/comp-test"
mkdir -p "$COMP_DIR/sessions"

# Create 3 past sessions with avg cost ~$0.10
for i in 1 2 3; do
  echo "{\"type\":\"snapshot\",\"timestamp\":\"2026-03-25T15:00:00Z\",\"session_id\":\"past-$i\",\"total_cost_usd\":0.10}" > "$COMP_DIR/sessions/past-$i.jsonl"
done

# Create native session with high cost (~$2.50 which is 25x average)
COMP_NATIVE="$TMPDIR/.claude/projects/-test-project/comp-sess.jsonl"
cat > "$COMP_NATIVE" <<'NATIVE'
{"type":"user","message":{"role":"user","content":"hello"},"timestamp":"2026-03-26T15:00:00.000Z","sessionId":"comp-sess"}
{"type":"assistant","message":{"role":"assistant","model":"claude-opus-4-6","usage":{"input_tokens":50000,"output_tokens":50000,"cache_read_input_tokens":10000,"cache_creation_input_tokens":5000}},"timestamp":"2026-03-26T15:05:00.000Z","sessionId":"comp-sess"}
NATIVE

COMP_OUT=$(echo '{"session_id":"comp-sess","hook_event_name":"PostToolUse","tool_name":"Bash"}' | HOME="$TMPDIR" CLAUDE_STATUS_DIR="$COMP_DIR" bash "$SCRIPT_DIR/snapshot-hook.sh" 2>&1)
if echo "$COMP_OUT" | grep -q "Expensive session"; then
  pass "expensive session alert fires"
else
  fail "expensive session alert fires" "output: $COMP_OUT"
fi

# ---------------------------------------------------------------------------
# snapshot-hook.sh — context watchdog + idle tests
# ---------------------------------------------------------------------------
echo ""
echo "=== snapshot-hook.sh — context & idle ==="

CTX_DIR="$TMPDIR/ctx-test"
mkdir -p "$CTX_DIR/sessions"

# Test: Sonnet with high context usage (tokens sum to >80% of 200k) triggers warning
CTX_NATIVE="$TMPDIR/.claude/projects/-test-project/ctx-sess.jsonl"
cat > "$CTX_NATIVE" <<'NATIVE'
{"type":"user","message":{"role":"user","content":"hello"},"timestamp":"2026-03-26T15:00:00.000Z","sessionId":"ctx-sess"}
{"type":"assistant","message":{"role":"assistant","model":"claude-sonnet-4-6","usage":{"input_tokens":80000,"output_tokens":40000,"cache_read_input_tokens":50000,"cache_creation_input_tokens":10000}},"timestamp":"2026-03-26T15:00:05.000Z","sessionId":"ctx-sess"}
NATIVE

CTX_OUT=$(echo '{"session_id":"ctx-sess","hook_event_name":"PostToolUse","tool_name":"Bash"}' | HOME="$TMPDIR" CLAUDE_STATUS_DIR="$CTX_DIR" bash "$SCRIPT_DIR/snapshot-hook.sh" 2>&1)
if echo "$CTX_OUT" | grep -q "Context"; then
  pass "Sonnet context warning fires at high usage (200k window)"
else
  fail "Sonnet context warning fires at high usage (200k window)" "output: $CTX_OUT"
fi

# Verify Sonnet snapshot has context_window_size=200000
CTX_SNAP=$(grep '"type":"snapshot"' "$CTX_DIR/sessions/ctx-sess.jsonl" | tail -1)
CTX_WIN=$(echo "$CTX_SNAP" | jq -r '.context_window_size')
if [ "$CTX_WIN" = "200000" ]; then
  pass "Sonnet snapshot has 200k context window"
else
  fail "Sonnet snapshot has 200k context window" "got: $CTX_WIN"
fi

# Test: Opus with same tokens does NOT trigger context warning (180k / 1M = 18%)
OPUS_CTX_DIR="$TMPDIR/opus-ctx-test"
mkdir -p "$OPUS_CTX_DIR/sessions"
OPUS_CTX_NATIVE="$TMPDIR/.claude/projects/-test-project/opus-ctx-sess.jsonl"
cat > "$OPUS_CTX_NATIVE" <<'NATIVE'
{"type":"user","message":{"role":"user","content":"hello"},"timestamp":"2026-03-26T15:00:00.000Z","sessionId":"opus-ctx-sess"}
{"type":"assistant","message":{"role":"assistant","model":"claude-opus-4-6","usage":{"input_tokens":80000,"output_tokens":40000,"cache_read_input_tokens":50000,"cache_creation_input_tokens":10000}},"timestamp":"2026-03-26T15:00:05.000Z","sessionId":"opus-ctx-sess"}
NATIVE

OPUS_CTX_OUT=$(echo '{"session_id":"opus-ctx-sess","hook_event_name":"PostToolUse","tool_name":"Bash"}' | HOME="$TMPDIR" CLAUDE_STATUS_DIR="$OPUS_CTX_DIR" bash "$SCRIPT_DIR/snapshot-hook.sh" 2>&1)
if echo "$OPUS_CTX_OUT" | grep -q "Context"; then
  fail "Opus no context warning at 18% (1M window)" "unexpected alert: $OPUS_CTX_OUT"
else
  pass "Opus no context warning at 18% (1M window)"
fi

# Verify Opus snapshot has context_window_size=1000000 and correct pct
OPUS_SNAP=$(grep '"type":"snapshot"' "$OPUS_CTX_DIR/sessions/opus-ctx-sess.jsonl" | tail -1)
OPUS_WIN=$(echo "$OPUS_SNAP" | jq -r '.context_window_size')
OPUS_PCT=$(echo "$OPUS_SNAP" | jq -r '.context_used_pct')
if [ "$OPUS_WIN" = "1000000" ]; then
  pass "Opus snapshot has 1M context window"
else
  fail "Opus snapshot has 1M context window" "got: $OPUS_WIN"
fi
if [ "$OPUS_PCT" = "18" ]; then
  pass "Opus context_used_pct is 18% (180k/1M)"
else
  fail "Opus context_used_pct is 18% (180k/1M)" "got: $OPUS_PCT"
fi

# ---------------------------------------------------------------------------
# subagent-hook.sh tests
# ---------------------------------------------------------------------------
echo ""
echo "=== subagent-hook.sh ==="

SA_DIR="$TMPDIR/sa-test"
mkdir -p "$SA_DIR/sessions"

# Create a mock subagent transcript
SA_TRANSCRIPT="$TMPDIR/subagent-transcript.jsonl"
cat > "$SA_TRANSCRIPT" <<'NATIVE'
{"type":"user","message":{"role":"user","content":"find files"},"timestamp":"2026-03-26T15:00:00.000Z"}
{"type":"assistant","message":{"role":"assistant","model":"claude-sonnet-4-6","usage":{"input_tokens":5000,"output_tokens":1000,"cache_read_input_tokens":2000,"cache_creation_input_tokens":500}},"timestamp":"2026-03-26T15:00:03.000Z"}
{"type":"assistant","message":{"role":"assistant","model":"claude-sonnet-4-6","usage":{"input_tokens":3000,"output_tokens":800,"cache_read_input_tokens":1000,"cache_creation_input_tokens":200}},"timestamp":"2026-03-26T15:00:06.000Z"}
NATIVE

SA_INPUT=$(jq -cn \
  --arg sid "sa-sess" \
  --arg agent_id "agent-abc123" \
  --arg agent_type "Explore" \
  --arg transcript "$SA_TRANSCRIPT" \
  '{session_id: $sid, hook_event_name: "SubagentStop", agent_id: $agent_id, agent_type: $agent_type, agent_transcript_path: $transcript}')

# Test 1: exits 0
SA_OUT=$(echo "$SA_INPUT" | CLAUDE_STATUS_DIR="$SA_DIR" bash "$SCRIPT_DIR/subagent-hook.sh" 2>&1) && pass "exits 0" || fail "exits 0" "non-zero exit"

# Test 2: writes subagent_event to JSONL
SA_JSONL="$SA_DIR/sessions/sa-sess.jsonl"
if [ -f "$SA_JSONL" ] && grep -q '"type":"subagent_event"' "$SA_JSONL"; then
  pass "writes subagent_event"
else
  fail "writes subagent_event" "no event in file"
fi

# Test 3: agent_type is captured
SA_TYPE=$(grep '"type":"subagent_event"' "$SA_JSONL" | jq -r '.agent_type')
if [ "$SA_TYPE" = "Explore" ]; then
  pass "agent_type captured"
else
  fail "agent_type captured" "got: $SA_TYPE"
fi

# Test 4: cost is computed (should be > 0)
SA_COST=$(grep '"type":"subagent_event"' "$SA_JSONL" | jq -r '.cost_usd')
if [ "$(awk "BEGIN{print ($SA_COST > 0) ? 1 : 0}")" = "1" ]; then
  pass "cost computed from transcript"
else
  fail "cost computed from transcript" "got: $SA_COST"
fi

# Test 5: model is detected
SA_MODEL=$(grep '"type":"subagent_event"' "$SA_JSONL" | jq -r '.model')
if echo "$SA_MODEL" | grep -qi "sonnet"; then
  pass "model detected from transcript"
else
  fail "model detected from transcript" "got: $SA_MODEL"
fi

# Test 6: output is {} for normal cost
if [ "$SA_OUT" = "{}" ]; then
  pass "no alert for normal cost"
else
  fail "no alert for normal cost" "output: $SA_OUT"
fi

# Test 7: alert fires for expensive subagent (> $2)
EXPENSIVE_TRANSCRIPT="$TMPDIR/expensive-transcript.jsonl"
cat > "$EXPENSIVE_TRANSCRIPT" <<'NATIVE'
{"type":"assistant","message":{"role":"assistant","model":"claude-opus-4-6","usage":{"input_tokens":200000,"output_tokens":50000,"cache_read_input_tokens":100000,"cache_creation_input_tokens":30000}},"timestamp":"2026-03-26T15:00:05.000Z"}
NATIVE

EXPENSIVE_INPUT=$(jq -cn \
  --arg sid "sa-sess" \
  --arg agent_id "agent-expensive" \
  --arg agent_type "Plan" \
  --arg transcript "$EXPENSIVE_TRANSCRIPT" \
  '{session_id: $sid, hook_event_name: "SubagentStop", agent_id: $agent_id, agent_type: $agent_type, agent_transcript_path: $transcript}')

EXPENSIVE_OUT=$(echo "$EXPENSIVE_INPUT" | CLAUDE_STATUS_DIR="$SA_DIR" bash "$SCRIPT_DIR/subagent-hook.sh" 2>&1)
if echo "$EXPENSIVE_OUT" | grep -q "Expensive subagent"; then
  pass "alert fires for expensive subagent"
else
  fail "alert fires for expensive subagent" "output: $EXPENSIVE_OUT"
fi

# Test 8: graceful with missing transcript
NO_TRANSCRIPT_INPUT=$(jq -cn \
  --arg sid "sa-sess2" \
  --arg agent_id "agent-none" \
  --arg agent_type "Explore" \
  '{session_id: $sid, hook_event_name: "SubagentStop", agent_id: $agent_id, agent_type: $agent_type, agent_transcript_path: "/nonexistent/path.jsonl"}')

SA_DIR2="$TMPDIR/sa-test2"
mkdir -p "$SA_DIR2/sessions"
NO_OUT=$(echo "$NO_TRANSCRIPT_INPUT" | CLAUDE_STATUS_DIR="$SA_DIR2" bash "$SCRIPT_DIR/subagent-hook.sh" 2>&1) && pass "graceful with missing transcript" || fail "graceful with missing transcript" "non-zero exit"

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
echo ""
echo "=== Results: $PASS passed, $FAIL failed ==="
if [ "$FAIL" -gt 0 ]; then
  exit 1
fi
