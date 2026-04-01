#!/bin/bash
# claude-status: Tracks compaction events via PostCompact hook
# Increments compaction counter for session metrics.

set -euo pipefail

INPUT=$(cat)
DATA_DIR="${CLAUDE_STATUS_DIR:-$HOME/.claude-status}"

SESSION_ID=$(echo "$INPUT" | jq -r '.session_id // "unknown"' 2>/dev/null)
if [ "$SESSION_ID" = "unknown" ] || [ "$SESSION_ID" = "null" ]; then
  echo "{}"
  exit 0
fi

# Increment compaction counter
STATS_FILE="$DATA_DIR/stats-${SESSION_ID}.json"
if [ ! -f "$STATS_FILE" ]; then
  echo '{"tools":{},"errors":0,"total_calls":0,"compactions":0}' > "$STATS_FILE"
fi

UPDATED=$(jq '.compactions = ((.compactions // 0) + 1)' "$STATS_FILE" 2>/dev/null)
if [ -n "$UPDATED" ]; then
  echo "$UPDATED" > "$STATS_FILE"
fi

echo "{}"
