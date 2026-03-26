#!/bin/bash
# claude-status: Task tracking hook for Claude Code
# Captures task create/update events and logs them for cost-per-task analysis.
#
# Configure in ~/.claude/settings.json:
#   "hooks": {
#     "PostToolUse": [{
#       "matcher": "TodoWrite",
#       "command": "bash ~/.claude-status/hooks/task-hook.sh"
#     }],
#     "TaskCompleted": [{
#       "command": "bash ~/.claude-status/hooks/task-hook.sh"
#     }]
#   }

set -euo pipefail

INPUT=$(cat)
DATA_DIR="${CLAUDE_STATUS_DIR:-$HOME/.claude-status}"
SESSION_DIR="$DATA_DIR/sessions"

SESSION_ID=$(echo "$INPUT" | jq -r '.session_id // "unknown"')
HOOK_EVENT=$(echo "$INPUT" | jq -r '.hook_event_name // "unknown"')
TOOL_NAME=$(echo "$INPUT" | jq -r '.tool_name // ""')
TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

mkdir -p "$SESSION_DIR"

LOG_FILE="$SESSION_DIR/${SESSION_ID}.jsonl"

# Read the latest snapshot cost for this session (for delta calculation)
COST_SNAP=0
TOKEN_SNAP=0
if [ -f "$LOG_FILE" ]; then
    LAST_SNAP=$(grep '"type":"snapshot"' "$LOG_FILE" | tail -1 2>/dev/null || echo "")
    if [ -n "$LAST_SNAP" ]; then
        COST_SNAP=$(echo "$LAST_SNAP" | jq -r '.total_cost_usd // 0')
        INPUT_TOK=$(echo "$LAST_SNAP" | jq -r '.total_input_tokens // 0')
        OUTPUT_TOK=$(echo "$LAST_SNAP" | jq -r '.total_output_tokens // 0')
        TOKEN_SNAP=$((INPUT_TOK + OUTPUT_TOK))
    fi
fi

case "$HOOK_EVENT" in
    "PostToolUse")
        if [ "$TOOL_NAME" = "TodoWrite" ]; then
            # Extract todos from tool_input
            TODOS=$(echo "$INPUT" | jq -c '.tool_input.todos // []')
            NUM_TODOS=$(echo "$TODOS" | jq 'length')

            for i in $(seq 0 $((NUM_TODOS - 1))); do
                TASK_CONTENT=$(echo "$TODOS" | jq -r ".[$i].content // \"\"")
                TASK_STATUS=$(echo "$TODOS" | jq -r ".[$i].status // \"pending\"")
                TASK_ID="task-$(echo "$TASK_CONTENT" | md5sum 2>/dev/null | cut -c1-8 || echo "$i")"

                EVENT_TYPE="task_updated"
                if [ "$TASK_STATUS" = "in_progress" ]; then
                    EVENT_TYPE="task_started"
                elif [ "$TASK_STATUS" = "completed" ]; then
                    EVENT_TYPE="task_completed"
                fi

                cat <<ENTRY >> "$LOG_FILE"
{"type":"task_event","timestamp":"$TIMESTAMP","session_id":"$SESSION_ID","event":"$EVENT_TYPE","task_id":"$TASK_ID","task_subject":"$TASK_CONTENT","task_status":"$TASK_STATUS","cost_snapshot_usd":$COST_SNAP,"token_snapshot":$TOKEN_SNAP}
ENTRY
            done
        fi
        ;;
    "TaskCompleted")
        TASK_ID=$(echo "$INPUT" | jq -r '.task_id // "unknown"')
        TASK_SUBJECT=$(echo "$INPUT" | jq -r '.task_subject // "unknown"')

        cat <<ENTRY >> "$LOG_FILE"
{"type":"task_event","timestamp":"$TIMESTAMP","session_id":"$SESSION_ID","event":"task_completed","task_id":"$TASK_ID","task_subject":"$TASK_SUBJECT","task_status":"completed","cost_snapshot_usd":$COST_SNAP,"token_snapshot":$TOKEN_SNAP}
ENTRY
        ;;
esac

# Output empty JSON (no-op response)
echo "{}"
