#!/bin/bash
# claude-status: Subagent cost tracking hook for Claude Code
# Fires on SubagentStop to calculate per-subagent cost from transcript.
# Works on macOS, Linux, and Windows (Git Bash/WSL).

set -euo pipefail

INPUT=$(cat)
DATA_DIR="${CLAUDE_STATUS_DIR:-$HOME/.claude-status}"
SESSION_DIR="$DATA_DIR/sessions"

# Extract fields from hook input
eval "$(echo "$INPUT" | jq -r '
  @sh "SESSION_ID=\(.session_id // "unknown")",
  @sh "AGENT_ID=\(.agent_id // "")",
  @sh "AGENT_TYPE=\(.agent_type // "unknown")",
  @sh "TRANSCRIPT=\(.agent_transcript_path // "")"
' | tr ',' '\n')"

if [ -z "$AGENT_ID" ] || [ "$SESSION_ID" = "unknown" ]; then
  echo "{}"
  exit 0
fi

mkdir -p "$SESSION_DIR"
LOG_FILE="$SESSION_DIR/${SESSION_ID}.jsonl"
TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

# Expand ~ in transcript path
TRANSCRIPT="${TRANSCRIPT/#\~/$HOME}"

# Parse the subagent transcript to compute cost
AGENT_COST=""
if [ -n "$TRANSCRIPT" ] && [ -f "$TRANSCRIPT" ]; then
  AGENT_COST=$(grep '"type":"assistant"' "$TRANSCRIPT" 2>/dev/null | jq -sc '
    if length == 0 then null else

    (last.message.model // "unknown") as $model |
    (if ($model | test("haiku"; "i")) then {in: 1, out: 5, cr: 0.10, cw: 1.25}
     elif ($model | test("sonnet"; "i")) then {in: 3, out: 15, cr: 0.30, cw: 3.75}
     else {in: 5, out: 25, cr: 0.50, cw: 6.25} end) as $prices |

    ([.[].message.usage.input_tokens // 0] | add) as $input |
    ([.[].message.usage.output_tokens // 0] | add) as $output |
    ([.[].message.usage.cache_read_input_tokens // 0] | add) as $cache_read |
    ([.[].message.usage.cache_creation_input_tokens // 0] | add) as $cache_write |

    (($input * $prices.in + $output * $prices.out + $cache_read * $prices.cr + $cache_write * $prices.cw) / 1000000) as $cost |

    {
      cost_usd: ($cost * 10000 | round / 10000),
      input_tokens: ($input + $cache_read),
      output_tokens: $output,
      model: $model
    }

    end
  ' 2>/dev/null)
fi

# Default values if transcript parsing failed
COST_USD=0
INPUT_TOKENS=0
OUTPUT_TOKENS=0
AGENT_MODEL="unknown"

if [ -n "$AGENT_COST" ] && [ "$AGENT_COST" != "null" ]; then
  eval "$(echo "$AGENT_COST" | jq -r '
    @sh "COST_USD=\(.cost_usd // 0)",
    @sh "INPUT_TOKENS=\(.input_tokens // 0)",
    @sh "OUTPUT_TOKENS=\(.output_tokens // 0)",
    @sh "AGENT_MODEL=\(.model // "unknown")"
  ' | tr ',' '\n')"
fi

# Write subagent event to session JSONL
jq -cn \
  --arg type "subagent_event" \
  --arg timestamp "$TIMESTAMP" \
  --arg session_id "$SESSION_ID" \
  --arg agent_id "$AGENT_ID" \
  --arg agent_type "$AGENT_TYPE" \
  --argjson cost_usd "$COST_USD" \
  --argjson input_tokens "$INPUT_TOKENS" \
  --argjson output_tokens "$OUTPUT_TOKENS" \
  --arg model "$AGENT_MODEL" \
  '{
    type: $type,
    timestamp: $timestamp,
    session_id: $session_id,
    agent_id: $agent_id,
    agent_type: $agent_type,
    cost_usd: $cost_usd,
    input_tokens: $input_tokens,
    output_tokens: $output_tokens,
    model: $model
  }' >> "$LOG_FILE"

# Alert if subagent was expensive (> $2)
ALERTS=""
if [ "$(echo "$COST_USD > 2" | bc 2>/dev/null)" = "1" ]; then
  COST_DISPLAY=$(printf '%.2f' "$COST_USD")
  ALERTS="Expensive subagent: ${AGENT_TYPE} cost \$${COST_DISPLAY}. Consider using Sonnet for this type of work."
fi

# Output
if [ -n "$ALERTS" ]; then
  jq -cn \
    --arg ctx "[claude-status] $ALERTS" \
    '{"hookSpecificOutput":{"hookEventName":"SubagentStop","additionalContext":$ctx}}'
else
  echo "{}"
fi
