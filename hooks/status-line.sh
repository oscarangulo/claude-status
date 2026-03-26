#!/bin/bash
# claude-status: Status line script for Claude Code
# Captures token/cost snapshots and logs them for the TUI dashboard.
#
# Configure in ~/.claude/settings.json:
#   "statusLineCMD": "bash ~/.claude-status/hooks/status-line.sh"
#
# Reads JSON from stdin (Claude Code status line data),
# logs a snapshot to ~/.claude-status/sessions/<session_id>.jsonl,
# and outputs a formatted status string to stdout.

set -euo pipefail

INPUT=$(cat)
DATA_DIR="${CLAUDE_STATUS_DIR:-$HOME/.claude-status}"
SESSION_DIR="$DATA_DIR/sessions"

# Extract fields with jq
SESSION_ID=$(echo "$INPUT" | jq -r '.session_id // "unknown"')
TOTAL_COST=$(echo "$INPUT" | jq -r '.cost.total_cost_usd // 0')
TOTAL_DURATION=$(echo "$INPUT" | jq -r '.cost.total_duration_ms // 0')
API_DURATION=$(echo "$INPUT" | jq -r '.cost.total_api_duration_ms // 0')
LINES_ADDED=$(echo "$INPUT" | jq -r '.cost.total_lines_added // 0')
LINES_REMOVED=$(echo "$INPUT" | jq -r '.cost.total_lines_removed // 0')
INPUT_TOK=$(echo "$INPUT" | jq -r '.context_window.current_usage.input_tokens // 0')
OUTPUT_TOK=$(echo "$INPUT" | jq -r '.context_window.current_usage.output_tokens // 0')
CACHE_READ=$(echo "$INPUT" | jq -r '.context_window.current_usage.cache_read_input_tokens // 0')
CACHE_WRITE=$(echo "$INPUT" | jq -r '.context_window.current_usage.cache_creation_input_tokens // 0')
CTX_SIZE=$(echo "$INPUT" | jq -r '.context_window.context_window_size // 0')
CTX_PCT=$(echo "$INPUT" | jq -r '.context_window.used_percentage // 0')
TOTAL_INPUT=$(echo "$INPUT" | jq -r '.context_window.total_input_tokens // 0')
TOTAL_OUTPUT=$(echo "$INPUT" | jq -r '.context_window.total_output_tokens // 0')
MODEL=$(echo "$INPUT" | jq -r '.model.display_name // "unknown"')

# Ensure session directory exists
mkdir -p "$SESSION_DIR"

# Write snapshot as JSONL
TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
cat <<EOF >> "$SESSION_DIR/${SESSION_ID}.jsonl"
{"type":"snapshot","timestamp":"$TIMESTAMP","session_id":"$SESSION_ID","total_cost_usd":$TOTAL_COST,"total_input_tokens":$TOTAL_INPUT,"total_output_tokens":$TOTAL_OUTPUT,"cache_read_tokens":$CACHE_READ,"cache_write_tokens":$CACHE_WRITE,"context_used_pct":$CTX_PCT,"context_window_size":$CTX_SIZE,"total_duration_ms":$TOTAL_DURATION,"total_api_duration_ms":$API_DURATION,"total_lines_added":$LINES_ADDED,"total_lines_removed":$LINES_REMOVED,"model":"$MODEL"}
EOF

# Output status display
printf "\$%.4f | %s | ctx:%s%%" "$TOTAL_COST" "$MODEL" "$CTX_PCT"
