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

case "$HOOK_EVENT" in
    "PostToolUse")
        if [ "$TOOL_NAME" = "TodoWrite" ]; then
            TODOS=$(echo "$INPUT" | jq -c '.tool_input.todos // []')
            NUM_TODOS=$(echo "$TODOS" | jq 'length')

            if [ "$NUM_TODOS" -eq 0 ]; then
                echo "{}"
                exit 0
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

echo "{}"
