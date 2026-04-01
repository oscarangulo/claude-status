#!/bin/bash
# claude-status: Task tracking hook for Claude Code
# Captures task create/update events and logs them for cost-per-task analysis.
# Works on macOS, Linux, and Windows (Git Bash/WSL).

set -euo pipefail

INPUT=$(cat)
DATA_DIR="${CLAUDE_STATUS_DIR:-$HOME/.claude-status}"
SESSION_DIR="$DATA_DIR/sessions"
RUN_ID=$(date -u +"%Y%m%dT%H%M%SZ")

# Single jq call for main fields
eval "$(echo "$INPUT" | jq -r '
  @sh "SESSION_ID=\(.session_id // "unknown")",
  @sh "HOOK_EVENT=\(.hook_event_name // "unknown")",
  @sh "TOOL_NAME=\(.tool_name // "")"
' | tr ',' '\n')"

TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

mkdir -p "$SESSION_DIR"
LOG_FILE="$SESSION_DIR/${SESSION_ID}.jsonl"

# Read the latest snapshot cost for this session (for delta calculation)
COST_SNAP=0
TOKEN_SNAP=0
if [ -f "$LOG_FILE" ]; then
    LAST_SNAP=$(grep '"type":"snapshot"' "$LOG_FILE" | tail -1 2>/dev/null || echo "")
    if [ -n "$LAST_SNAP" ]; then
        eval "$(echo "$LAST_SNAP" | jq -r '
          @sh "COST_SNAP=\(.total_cost_usd // 0)",
          @sh "S_INPUT_TOK=\(.total_input_tokens // 0)",
          @sh "S_OUTPUT_TOK=\(.total_output_tokens // 0)"
        ' | tr ',' '\n')"
        TOKEN_SNAP=$((S_INPUT_TOK + S_OUTPUT_TOK))
    fi
fi

# Cross-platform hash: try md5sum (Linux), then md5 (macOS), fallback to cksum
hash_string() {
  if command -v md5sum >/dev/null 2>&1; then
    echo -n "$1" | md5sum | cut -c1-8
  elif command -v md5 >/dev/null 2>&1; then
    echo -n "$1" | md5 | cut -c1-8
  else
    echo -n "$1" | cksum | cut -d' ' -f1
  fi
}

emit_task_event() {
  local event_type="$1"
  local task_id="$2"
  local task_key="$3"
  local task_subject="$4"
  local task_status="$5"

  jq -cn \
    --arg type "task_event" \
    --arg timestamp "$TIMESTAMP" \
    --arg session_id "$SESSION_ID" \
    --arg event "$event_type" \
    --arg task_id "$task_id" \
    --arg task_key "$task_key" \
    --arg task_subject "$task_subject" \
    --arg task_status "$task_status" \
    --argjson cost_snapshot_usd "$COST_SNAP" \
    --argjson token_snapshot "$TOKEN_SNAP" \
    '{
      type: $type,
      timestamp: $timestamp,
      session_id: $session_id,
      event: $event,
      task_id: $task_id,
      task_key: $task_key,
      task_subject: $task_subject,
      task_status: $task_status,
      cost_snapshot_usd: $cost_snapshot_usd,
      token_snapshot: $token_snapshot
    }' >> "$LOG_FILE"
}

# --- Plan cost estimation ---
# Computes average cost per task from completed tasks across all sessions.
# Returns the estimate via additionalContext when a new plan is created.
compute_plan_estimate() {
  local num_tasks="$1"
  local alerts=""

  # Gather completed task pairs (started + completed) to compute avg cost
  AVG_TASK_COST=0
  COMPLETED_TASKS=0

  for sf in "$SESSION_DIR"/*.jsonl; do
    [ -f "$sf" ] || continue
    # Find task_completed events that have cost data
    while IFS= read -r line; do
      TASK_KEY_C=$(echo "$line" | jq -r '.task_key // ""')
      END_COST=$(echo "$line" | jq -r '.cost_snapshot_usd // 0')

      # Find matching task_started for this task_key
      START_LINE=$(grep "\"event\":\"task_started\"" "$sf" 2>/dev/null | grep "\"task_key\":\"$TASK_KEY_C\"" | tail -1 || echo "")
      if [ -n "$START_LINE" ]; then
        START_COST=$(echo "$START_LINE" | jq -r '.cost_snapshot_usd // 0')
        DELTA=$(echo "scale=4; $END_COST - $START_COST" | bc 2>/dev/null || echo "0")
        if [ "$(echo "$DELTA > 0" | bc 2>/dev/null)" = "1" ]; then
          AVG_TASK_COST=$(echo "scale=4; $AVG_TASK_COST + $DELTA" | bc 2>/dev/null)
          COMPLETED_TASKS=$((COMPLETED_TASKS + 1))
        fi
      fi
    done < <(grep '"event":"task_completed"' "$sf" 2>/dev/null || true)
  done

  if [ "$COMPLETED_TASKS" -ge 2 ]; then
    AVG_PER_TASK=$(echo "scale=4; $AVG_TASK_COST / $COMPLETED_TASKS" | bc 2>/dev/null || echo "0")
    ESTIMATED_TOTAL=$(echo "scale=2; $AVG_PER_TASK * $num_tasks" | bc 2>/dev/null || echo "0")
    AVG_DISPLAY=$(printf '%.2f' "$AVG_PER_TASK")
    EST_DISPLAY=$(printf '%.2f' "$ESTIMATED_TOTAL")

    alerts="Plan estimate: ${num_tasks} tasks x \$${AVG_DISPLAY} avg = ~\$${EST_DISPLAY}."

    # Check against budget
    BUDGET_FILE="$DATA_DIR/budget.json"
    if [ -f "$BUDGET_FILE" ]; then
      DAILY_LIMIT=$(jq -r '.daily_limit // 0' "$BUDGET_FILE" 2>/dev/null)
      if [ "$(echo "$DAILY_LIMIT > 0" | bc 2>/dev/null)" = "1" ]; then
        # Get today's total spend across all sessions
        TODAY=$(date -u +"%Y-%m-%d")
        TODAY_SPEND=0
        for sf in "$SESSION_DIR"/*.jsonl; do
          [ -f "$sf" ] || continue
          LAST_SNAP=$(grep '"type":"snapshot"' "$sf" 2>/dev/null | tail -1 || echo "")
          if [ -n "$LAST_SNAP" ]; then
            SNAP_DATE=$(echo "$LAST_SNAP" | jq -r '.timestamp // ""' | cut -c1-10)
            if [ "$SNAP_DATE" = "$TODAY" ]; then
              SNAP_COST=$(echo "$LAST_SNAP" | jq -r '.total_cost_usd // 0')
              TODAY_SPEND=$(echo "scale=4; $TODAY_SPEND + $SNAP_COST" | bc 2>/dev/null)
            fi
          fi
        done

        REMAINING=$(echo "scale=2; $DAILY_LIMIT - $TODAY_SPEND" | bc 2>/dev/null || echo "0")
        REM_DISPLAY=$(printf '%.2f' "$REMAINING")

        if [ "$(echo "$ESTIMATED_TOTAL > $REMAINING" | bc 2>/dev/null)" = "1" ]; then
          alerts="${alerts} WARNING: This may exceed your remaining budget (\$${REM_DISPLAY}). Consider splitting into phases or using Sonnet."
        else
          alerts="${alerts} Budget remaining: \$${REM_DISPLAY}. This plan fits within your daily limit."
        fi
      fi
    fi
  else
    alerts="Plan created: ${num_tasks} tasks. Not enough task history to estimate cost (need 2+ completed tasks)."
  fi

  echo "$alerts"
}

PLAN_ALERT=""

case "$HOOK_EVENT" in
    "PostToolUse")
        if [ "$TOOL_NAME" = "TodoWrite" ]; then
            TODOS=$(echo "$INPUT" | jq -c '.tool_input.todos // []')
            NUM_TODOS=$(echo "$TODOS" | jq 'length')

            if [ "$NUM_TODOS" -eq 0 ]; then
                echo "{}"
                exit 0
            fi

            # Detect new plan: count pending/in_progress tasks that are NEW (no prior events)
            NEW_PLAN_TASKS=0
            for i in $(seq 0 $((NUM_TODOS - 1))); do
                TASK_CONTENT=$(echo "$TODOS" | jq -r ".[$i].content // \"\"")
                TASK_STATUS=$(echo "$TODOS" | jq -r ".[$i].status // \"pending\"")
                TASK_KEY="task-$(hash_string "$TASK_CONTENT")"
                EXISTING=$(grep "\"task_key\":\"$TASK_KEY\"" "$LOG_FILE" 2>/dev/null | tail -1 || echo "")
                if [ -z "$EXISTING" ] && [ "$TASK_STATUS" != "completed" ]; then
                    NEW_PLAN_TASKS=$((NEW_PLAN_TASKS + 1))
                fi
            done

            # If 3+ new tasks, this is a new plan — estimate cost
            if [ "$NEW_PLAN_TASKS" -ge 3 ]; then
                PLAN_ALERT=$(compute_plan_estimate "$NEW_PLAN_TASKS")
            fi

            for i in $(seq 0 $((NUM_TODOS - 1))); do
                TASK_CONTENT=$(echo "$TODOS" | jq -r ".[$i].content // \"\"")
                TASK_STATUS=$(echo "$TODOS" | jq -r ".[$i].status // \"pending\"")
                TASK_KEY="task-$(hash_string "$TASK_CONTENT")"
                LAST_EVENT=$(grep "\"task_key\":\"$TASK_KEY\"" "$LOG_FILE" 2>/dev/null | tail -1 || echo "")
                LAST_STATUS=""
                LAST_TASK_ID=""
                if [ -n "$LAST_EVENT" ]; then
                    LAST_STATUS=$(echo "$LAST_EVENT" | jq -r '.task_status // ""')
                    LAST_TASK_ID=$(echo "$LAST_EVENT" | jq -r '.task_id // ""')
                fi

                EVENT_TYPE=""
                TASK_ID="$LAST_TASK_ID"
                if [ "$TASK_STATUS" = "in_progress" ] && [ "$LAST_STATUS" != "in_progress" ]; then
                    EVENT_TYPE="task_started"
                    TASK_ID="${TASK_KEY}-${RUN_ID}-${i}"
                elif [ "$TASK_STATUS" = "completed" ] && [ "$LAST_STATUS" != "completed" ]; then
                    EVENT_TYPE="task_completed"
                    if [ -z "$TASK_ID" ]; then
                        TASK_ID="${TASK_KEY}-${RUN_ID}-${i}"
                    fi
                elif [ "$TASK_STATUS" != "$LAST_STATUS" ] && [ -n "$LAST_STATUS" ]; then
                    EVENT_TYPE="task_updated"
                    if [ -z "$TASK_ID" ]; then
                        TASK_ID="${TASK_KEY}-${RUN_ID}-${i}"
                    fi
                fi

                if [ -n "$EVENT_TYPE" ]; then
                    emit_task_event "$EVENT_TYPE" "$TASK_ID" "$TASK_KEY" "$TASK_CONTENT" "$TASK_STATUS"
                fi
            done
        fi
        ;;
esac

# Output: if we have a plan estimate, send it as additionalContext
if [ -n "$PLAN_ALERT" ]; then
    jq -cn \
      --arg ctx "[claude-status] $PLAN_ALERT" \
      '{"hookSpecificOutput":{"hookEventName":"PostToolUse","additionalContext":$ctx}}'
else
    echo "{}"
fi
