#!/bin/bash
# claude-status: Lightweight pulse hook for Stop event
# Shows periodic session summary after every N responses (including pure conversation).
# Reads last snapshot from session JSONL — no heavy computation.

set -euo pipefail

INPUT=$(cat)
DATA_DIR="${CLAUDE_STATUS_DIR:-$HOME/.claude-status}"
SESSION_DIR="$DATA_DIR/sessions"
BUDGET_FILE="$DATA_DIR/budget.json"

SESSION_ID=$(echo "$INPUT" | jq -r '.session_id // "unknown"' 2>/dev/null)
if [ "$SESSION_ID" = "unknown" ] || [ "$SESSION_ID" = "null" ]; then
  echo "{}"
  exit 0
fi

LOG_FILE="$SESSION_DIR/${SESSION_ID}.jsonl"
if [ ! -f "$LOG_FILE" ]; then
  echo "{}"
  exit 0
fi

# Pulse frequency (default: 3)
PULSE_EVERY=3
if [ -f "$BUDGET_FILE" ]; then
  CONFIGURED_PULSE=$(jq -r '.pulse_every // 0' "$BUDGET_FILE" 2>/dev/null)
  if [ "$CONFIGURED_PULSE" -gt 0 ] 2>/dev/null; then
    PULSE_EVERY=$CONFIGURED_PULSE
  fi
fi

# Increment pulse counter
PULSE_FILE="$DATA_DIR/pulse-${SESSION_ID}"
PULSE_COUNT=0
if [ -f "$PULSE_FILE" ]; then
  PULSE_COUNT=$(cat "$PULSE_FILE" 2>/dev/null || echo "0")
fi
PULSE_COUNT=$((PULSE_COUNT + 1))
echo "$PULSE_COUNT" > "$PULSE_FILE"

if [ $(( PULSE_COUNT % PULSE_EVERY )) -ne 0 ]; then
  echo "{}"
  exit 0
fi

# Read last snapshot for metrics
LAST_SNAP=$(grep '"type":"snapshot"' "$LOG_FILE" 2>/dev/null | tail -1 || echo "")
if [ -z "$LAST_SNAP" ]; then
  echo "{}"
  exit 0
fi

NEW_COST=$(echo "$LAST_SNAP" | jq -r '.total_cost_usd // 0')
NEW_CTX=$(echo "$LAST_SNAP" | jq -r '.context_used_pct // 0')
DURATION_MS=$(echo "$LAST_SNAP" | jq -r '.total_duration_ms // 0')
DURATION_MIN=$(awk "BEGIN{d=$DURATION_MS/60000; printf \"%d\", (d > 0) ? d : 0}" 2>/dev/null)

# Detect plan mode
PLAN_MODE=""
if [ -f "$BUDGET_FILE" ]; then
  PLAN_MODE=$(jq -r '.plan // ""' "$BUDGET_FILE" 2>/dev/null)
fi

if [ "$PLAN_MODE" = "pro" ]; then
  # Pro mode: productivity pulse
  TOTAL_TOKENS=$(echo "$LAST_SNAP" | jq -r '(.total_input_tokens // 0) + (.total_output_tokens // 0)')
  TOKENS_DISPLAY=$(awk "BEGIN{t=$TOTAL_TOKENS; if(t>=1000000) printf \"%.1fM\",t/1000000; else if(t>=1000) printf \"%.0fK\",t/1000; else printf \"%d\",t}" 2>/dev/null)
  LINES_ADDED=$(echo "$LAST_SNAP" | jq -r '.total_lines_added // 0')
  LINES_REMOVED=$(echo "$LAST_SNAP" | jq -r '.total_lines_removed // 0')
  LINES_INFO=""
  if [ "$LINES_ADDED" -gt 0 ] || [ "$LINES_REMOVED" -gt 0 ]; then
    LINES_INFO=", +${LINES_ADDED}/-${LINES_REMOVED} lines"
  fi
  TIME_INFO=""
  if [ "$DURATION_MIN" -gt 0 ]; then
    TIME_INFO=", ${DURATION_MIN}min"
  fi
  TASK_COUNT=0
  if [ -f "$LOG_FILE" ]; then
    TASK_COUNT=$(grep -c '"event":"task_completed"' "$LOG_FILE" 2>/dev/null || echo "0")
  fi
  TASK_INFO=""
  if [ "$TASK_COUNT" -gt 0 ]; then
    TASK_INFO="${TASK_COUNT} tasks done, "
  fi
  ALERT="Session: ${TASK_INFO}${TOKENS_DISPLAY} tokens, ${NEW_CTX}% context${LINES_INFO}${TIME_INFO}."
else
  # API mode: cost pulse
  BURN_DISPLAY=""
  if [ "$DURATION_MIN" -gt 0 ]; then
    PULSE_BURN=$(awk "BEGIN{printf \"%.2f\", $NEW_COST / $DURATION_MIN}" 2>/dev/null || echo "0")
    BURN_DISPLAY=", \$${PULSE_BURN}/min"
  fi
  COST_DISPLAY=$(printf '%.2f' "$NEW_COST")
  ALERT="Session: \$${COST_DISPLAY} spent, ${NEW_CTX}% context${BURN_DISPLAY}."
fi

jq -cn --arg ctx "[claude-status] IMPORTANT: Show this alert to the user on its own line before your response: $ALERT" '{
  "hookSpecificOutput": {
    "hookEventName": "Stop",
    "additionalContext": $ctx
  }
}'
