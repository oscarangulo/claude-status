#!/bin/bash
# claude-status: Session pulse hook (Stop event)
# Shows periodic session summary after every N responses.
# Reads snapshot + stats for rich productivity metrics.

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

# Read last snapshot
LAST_SNAP=$(grep '"type":"snapshot"' "$LOG_FILE" 2>/dev/null | tail -1 || echo "")
if [ -z "$LAST_SNAP" ]; then
  echo "{}"
  exit 0
fi

NEW_COST=$(echo "$LAST_SNAP" | jq -r '.total_cost_usd // 0')
NEW_CTX=$(echo "$LAST_SNAP" | jq -r '.context_used_pct // 0')
DURATION_MS=$(echo "$LAST_SNAP" | jq -r '.total_duration_ms // 0')
DURATION_MIN=$(awk "BEGIN{d=$DURATION_MS/60000; printf \"%d\", (d > 0) ? d : 0}" 2>/dev/null)
INPUT_TOKENS=$(echo "$LAST_SNAP" | jq -r '.total_input_tokens // 0')
CACHE_READ=$(echo "$LAST_SNAP" | jq -r '.cache_read_tokens // 0')
LINES_ADDED=$(echo "$LAST_SNAP" | jq -r '.total_lines_added // 0')
LINES_REMOVED=$(echo "$LAST_SNAP" | jq -r '.total_lines_removed // 0')

# Default to pro (subscription)
PLAN_MODE="pro"
if [ -f "$BUDGET_FILE" ]; then
  CONFIGURED_PLAN=$(jq -r '.plan // ""' "$BUDGET_FILE" 2>/dev/null)
  if [ -n "$CONFIGURED_PLAN" ]; then
    PLAN_MODE="$CONFIGURED_PLAN"
  fi
fi

# Read session stats (tool breakdown, errors, compactions)
STATS_FILE="$DATA_DIR/stats-${SESSION_ID}.json"
TOTAL_CALLS=0
TOTAL_ERRORS=0
COMPACTIONS=0
TOP_TOOLS=""
if [ -f "$STATS_FILE" ]; then
  TOTAL_CALLS=$(jq -r '.total_calls // 0' "$STATS_FILE" 2>/dev/null)
  TOTAL_ERRORS=$(jq -r '.errors // 0' "$STATS_FILE" 2>/dev/null)
  COMPACTIONS=$(jq -r '.compactions // 0' "$STATS_FILE" 2>/dev/null)
  # Get top 3 tools by usage
  TOP_TOOLS=$(jq -r '.tools | to_entries | sort_by(-.value) | .[0:3] | map("\(.key):\(.value)") | join(" ")' "$STATS_FILE" 2>/dev/null || echo "")
fi

# Cache hit rate
CACHE_HIT=0
TOTAL_IN=$((INPUT_TOKENS))
if [ "$TOTAL_IN" -gt 0 ] && [ "$CACHE_READ" -gt 0 ]; then
  CACHE_HIT=$(awk "BEGIN{printf \"%d\", $CACHE_READ * 100 / $TOTAL_IN}" 2>/dev/null)
fi

# Completed tasks
TASK_COUNT=$(grep -c '"event":"task_completed"' "$LOG_FILE" 2>/dev/null || true)
TASK_COUNT=${TASK_COUNT:-0}

if [ "$PLAN_MODE" = "pro" ]; then
  # --- PRO MODE: Productivity pulse ---
  TOTAL_TOKENS=$(echo "$LAST_SNAP" | jq -r '(.total_input_tokens // 0) + (.total_output_tokens // 0)')
  TOKENS_DISPLAY=$(awk "BEGIN{t=$TOTAL_TOKENS; if(t>=1000000) printf \"%.1fM\",t/1000000; else if(t>=1000) printf \"%.0fK\",t/1000; else printf \"%d\",t}" 2>/dev/null)

  # Build parts
  PARTS=""

  # Tasks
  if [ "$TASK_COUNT" -gt 0 ]; then
    PARTS="${TASK_COUNT} tasks"
  fi

  # Tokens
  PARTS="${PARTS:+$PARTS, }${TOKENS_DISPLAY} tokens"

  # Context
  PARTS="$PARTS, ${NEW_CTX}% ctx"

  # Cache hit
  if [ "$CACHE_HIT" -gt 0 ]; then
    PARTS="$PARTS, ${CACHE_HIT}% cache"
  fi

  # Lines
  if [ "$LINES_ADDED" -gt 0 ] || [ "$LINES_REMOVED" -gt 0 ]; then
    PARTS="$PARTS, +${LINES_ADDED}/-${LINES_REMOVED} lines"
  fi

  # Tool calls & errors
  if [ "$TOTAL_CALLS" -gt 0 ]; then
    TOOL_INFO="${TOTAL_CALLS} calls"
    if [ "$TOTAL_ERRORS" -gt 0 ]; then
      ERROR_PCT=$(awk "BEGIN{printf \"%d\", $TOTAL_ERRORS * 100 / $TOTAL_CALLS}" 2>/dev/null)
      TOOL_INFO="$TOOL_INFO (${ERROR_PCT}% errors)"
    fi
    PARTS="$PARTS, $TOOL_INFO"
  fi

  # Top tools
  if [ -n "$TOP_TOOLS" ]; then
    PARTS="$PARTS | top: $TOP_TOOLS"
  fi

  # Compactions
  if [ "$COMPACTIONS" -gt 0 ]; then
    PARTS="$PARTS, ${COMPACTIONS}x compacted"
  fi

  # Time
  if [ "$DURATION_MIN" -gt 0 ]; then
    # Velocity: context %/min
    CTX_VEL=$(awk "BEGIN{printf \"%.1f\", $NEW_CTX / $DURATION_MIN}" 2>/dev/null)
    PARTS="$PARTS, ${DURATION_MIN}min (${CTX_VEL}% ctx/min)"
  fi

  ALERT="$PARTS"
else
  # --- API MODE: Cost pulse ---
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
