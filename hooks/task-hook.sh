#!/bin/bash
# claude-status: Task tracking hook for Claude Code
# Captures task create/update events and logs them for cost-per-task analysis.
# Works on macOS, Linux, and Windows (Git Bash/WSL).

set -euo pipefail

INPUT=$(cat)
DATA_DIR="${CLAUDE_STATUS_DIR:-$HOME/.claude-status}"
SESSION_DIR="$DATA_DIR/sessions"

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

case "$HOOK_EVENT" in
    "PostToolUse")
        if [ "$TOOL_NAME" = "TodoWrite" ]; then
            TODOS=$(echo "$INPUT" | jq -c '.tool_input.todos // []')
            NUM_TODOS=$(echo "$TODOS" | jq 'length')

            for i in $(seq 0 $((NUM_TODOS - 1))); do
                TASK_CONTENT=$(echo "$TODOS" | jq -r ".[$i].content // \"\"")
                TASK_STATUS=$(echo "$TODOS" | jq -r ".[$i].status // \"pending\"")
                TASK_ID="task-$(hash_string "$TASK_CONTENT")"

                EVENT_TYPE="task_updated"
                if [ "$TASK_STATUS" = "in_progress" ]; then
                    EVENT_TYPE="task_started"
                elif [ "$TASK_STATUS" = "completed" ]; then
                    EVENT_TYPE="task_completed"
                fi

                # Escape double quotes in task content for valid JSON
                ESCAPED_CONTENT=$(echo "$TASK_CONTENT" | sed 's/"/\\"/g')

                printf '{"type":"task_event","timestamp":"%s","session_id":"%s","event":"%s","task_id":"%s","task_subject":"%s","task_status":"%s","cost_snapshot_usd":%s,"token_snapshot":%s}\n' \
                  "$TIMESTAMP" "$SESSION_ID" "$EVENT_TYPE" "$TASK_ID" "$ESCAPED_CONTENT" "$TASK_STATUS" "$COST_SNAP" "$TOKEN_SNAP" >> "$LOG_FILE"
            done
        fi
        ;;
    "TaskCompleted")
        TASK_ID=$(echo "$INPUT" | jq -r '.task_id // "unknown"')
        TASK_SUBJECT=$(echo "$INPUT" | jq -r '.task_subject // "unknown"' | sed 's/"/\\"/g')

        printf '{"type":"task_event","timestamp":"%s","session_id":"%s","event":"task_completed","task_id":"%s","task_subject":"%s","task_status":"completed","cost_snapshot_usd":%s,"token_snapshot":%s}\n' \
          "$TIMESTAMP" "$SESSION_ID" "$TASK_ID" "$TASK_SUBJECT" "$COST_SNAP" "$TOKEN_SNAP" >> "$LOG_FILE"
        ;;
esac

echo "{}"
