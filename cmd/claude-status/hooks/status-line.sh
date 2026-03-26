#!/bin/bash
# claude-status: Rich status line for Claude Code
#
# Shows real-time cost, tokens, cache efficiency, context usage,
# and current task info — all inline in Claude Code's status bar.
#
# Configure in ~/.claude/settings.json:
#   "statusLineCMD": "bash ~/.claude-status/hooks/status-line.sh"

set -euo pipefail

INPUT=$(cat)
DATA_DIR="${CLAUDE_STATUS_DIR:-$HOME/.claude-status}"
SESSION_DIR="$DATA_DIR/sessions"

# Single jq call to extract everything at once (fast!)
eval "$(echo "$INPUT" | jq -r '
  @sh "SESSION_ID=\(.session_id // "unknown")",
  @sh "TOTAL_COST=\(.cost.total_cost_usd // 0)",
  @sh "TOTAL_DURATION=\(.cost.total_duration_ms // 0)",
  @sh "API_DURATION=\(.cost.total_api_duration_ms // 0)",
  @sh "LINES_ADDED=\(.cost.total_lines_added // 0)",
  @sh "LINES_REMOVED=\(.cost.total_lines_removed // 0)",
  @sh "TOTAL_INPUT=\(.context_window.total_input_tokens // 0)",
  @sh "TOTAL_OUTPUT=\(.context_window.total_output_tokens // 0)",
  @sh "CACHE_READ=\(.context_window.current_usage.cache_read_input_tokens // 0)",
  @sh "CACHE_WRITE=\(.context_window.current_usage.cache_creation_input_tokens // 0)",
  @sh "CTX_SIZE=\(.context_window.context_window_size // 0)",
  @sh "CTX_PCT=\(.context_window.used_percentage // 0)",
  @sh "INPUT_TOK=\(.context_window.current_usage.input_tokens // 0)",
  @sh "OUTPUT_TOK=\(.context_window.current_usage.output_tokens // 0)",
  @sh "MODEL=\(.model.display_name // "unknown")"
' | tr ',' '\n')"

# --- Log snapshot to JSONL ---
mkdir -p "$SESSION_DIR"
TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
LOG_FILE="$SESSION_DIR/${SESSION_ID}.jsonl"

printf '{"type":"snapshot","timestamp":"%s","session_id":"%s","total_cost_usd":%s,"total_input_tokens":%s,"total_output_tokens":%s,"cache_read_tokens":%s,"cache_write_tokens":%s,"context_used_pct":%s,"context_window_size":%s,"total_duration_ms":%s,"total_api_duration_ms":%s,"total_lines_added":%s,"total_lines_removed":%s,"model":"%s"}\n' \
  "$TIMESTAMP" "$SESSION_ID" "$TOTAL_COST" "$TOTAL_INPUT" "$TOTAL_OUTPUT" \
  "$CACHE_READ" "$CACHE_WRITE" "$CTX_PCT" "$CTX_SIZE" "$TOTAL_DURATION" \
  "$API_DURATION" "$LINES_ADDED" "$LINES_REMOVED" "$MODEL" >> "$LOG_FILE"

# --- Format tokens for display ---
format_tok() {
  local n=$1
  if [ "$n" -ge 1000000 ]; then
    printf "%.1fM" "$(echo "scale=1; $n / 1000000" | bc)"
  elif [ "$n" -ge 1000 ]; then
    printf "%.1fK" "$(echo "scale=1; $n / 1000" | bc)"
  else
    printf "%d" "$n"
  fi
}

# --- Calculate cache hit rate ---
TOTAL_IN=$((INPUT_TOK + CACHE_READ))
if [ "$TOTAL_IN" -gt 0 ]; then
  CACHE_HIT=$(echo "scale=0; $CACHE_READ * 100 / $TOTAL_IN" | bc)
else
  CACHE_HIT=0
fi

# --- Format duration ---
if [ "$TOTAL_DURATION" -gt 0 ]; then
  SECS=$((TOTAL_DURATION / 1000))
  if [ "$SECS" -ge 3600 ]; then
    DURATION="$(($SECS / 3600))h$(($SECS % 3600 / 60))m"
  elif [ "$SECS" -ge 60 ]; then
    DURATION="$(($SECS / 60))m$(($SECS % 60))s"
  else
    DURATION="${SECS}s"
  fi
else
  DURATION="0s"
fi

# --- Context bar (visual) ---
# 5 chars: filled/empty blocks proportional to usage
BAR_LEN=5
FILLED=$((CTX_PCT * BAR_LEN / 100))
if [ "$FILLED" -gt "$BAR_LEN" ]; then FILLED=$BAR_LEN; fi
EMPTY=$((BAR_LEN - FILLED))
CTX_BAR=$(printf '%0.s█' $(seq 1 $FILLED 2>/dev/null) ; printf '%0.s░' $(seq 1 $EMPTY 2>/dev/null))

# --- Context warning ---
CTX_WARN=""
if [ "$CTX_PCT" -ge 80 ]; then
  CTX_WARN=" ⚠"
elif [ "$CTX_PCT" -ge 60 ]; then
  CTX_WARN=" △"
fi

# --- Current task (read from log) ---
TASK_INFO=""
if [ -f "$LOG_FILE" ]; then
  # Find the last task_started event that hasn't been completed
  LAST_STARTED=$(grep '"event":"task_started"' "$LOG_FILE" 2>/dev/null | tail -1 || echo "")
  if [ -n "$LAST_STARTED" ]; then
    TASK_SUBJECT=$(echo "$LAST_STARTED" | jq -r '.task_subject // ""')
    TASK_COST_START=$(echo "$LAST_STARTED" | jq -r '.cost_snapshot_usd // 0')

    # Check if it was completed
    TASK_ID=$(echo "$LAST_STARTED" | jq -r '.task_id // ""')
    COMPLETED=$(grep "\"task_id\":\"$TASK_ID\".*\"event\":\"task_completed\"" "$LOG_FILE" 2>/dev/null | tail -1 || echo "")

    if [ -z "$COMPLETED" ]; then
      # Task is still running — show its cost so far
      TASK_DELTA=$(echo "scale=4; $TOTAL_COST - $TASK_COST_START" | bc)
      # Truncate subject to 20 chars
      if [ ${#TASK_SUBJECT} -gt 20 ]; then
        TASK_SUBJECT="${TASK_SUBJECT:0:17}..."
      fi
      TASK_INFO=" | ▸ ${TASK_SUBJECT} \$${TASK_DELTA}"
    fi
  fi
fi

# --- Lines changed ---
LINES_INFO=""
if [ "$LINES_ADDED" -gt 0 ] || [ "$LINES_REMOVED" -gt 0 ]; then
  LINES_INFO=" | +${LINES_ADDED}/-${LINES_REMOVED}"
fi

# --- Assemble status line ---
# Format: $0.1234 | 45.2K tok | cache:62% | ██░░░ 34% | 6m32s | +120/-5 | ▸ Task name $0.04
TOTAL_TOK=$((TOTAL_INPUT + TOTAL_OUTPUT))
printf "\$%.4f | %s tok | cache:%s%% | %s %s%%%s | %s%s%s" \
  "$TOTAL_COST" \
  "$(format_tok $TOTAL_TOK)" \
  "$CACHE_HIT" \
  "$CTX_BAR" "$CTX_PCT" "$CTX_WARN" \
  "$DURATION" \
  "$LINES_INFO" \
  "$TASK_INFO"
