#!/bin/bash
# claude-status: Pulse counter for Stop event
# Increments the pulse counter on every response (including pure conversation).
# The actual pulse message is emitted by snapshot-hook.sh via PostToolUse,
# since only PostToolUse supports additionalContext output.

set -euo pipefail

INPUT=$(cat)
DATA_DIR="${CLAUDE_STATUS_DIR:-$HOME/.claude-status}"

SESSION_ID=$(echo "$INPUT" | jq -r '.session_id // "unknown"' 2>/dev/null)
if [ "$SESSION_ID" = "unknown" ] || [ "$SESSION_ID" = "null" ]; then
  echo "{}"
  exit 0
fi

# Increment pulse counter (shared with snapshot-hook)
PULSE_FILE="$DATA_DIR/pulse-${SESSION_ID}"
PULSE_COUNT=0
if [ -f "$PULSE_FILE" ]; then
  PULSE_COUNT=$(cat "$PULSE_FILE" 2>/dev/null || echo "0")
fi
PULSE_COUNT=$((PULSE_COUNT + 1))
echo "$PULSE_COUNT" > "$PULSE_FILE"

echo "{}"
