#!/bin/bash
# claude-status: Snapshot hook for Claude Code
# Generates cost/token snapshots from Claude Code's native session data.
# Works in both terminal CLI and VS Code extension (unlike statusLine).
# Fires on every PostToolUse event (no matcher).

set -euo pipefail

INPUT=$(cat)
DATA_DIR="${CLAUDE_STATUS_DIR:-$HOME/.claude-status}"
SESSION_DIR="$DATA_DIR/sessions"
CLAUDE_DIR="$HOME/.claude/projects"

# Extract session_id from hook input
SESSION_ID=$(echo "$INPUT" | jq -r '.session_id // "unknown"')
if [ "$SESSION_ID" = "unknown" ] || [ "$SESSION_ID" = "null" ]; then
  echo "{}"
  exit 0
fi

mkdir -p "$SESSION_DIR"
LOG_FILE="$SESSION_DIR/${SESSION_ID}.jsonl"

# Find the native Claude Code session file
NATIVE_FILE=$(find "$CLAUDE_DIR" -name "${SESSION_ID}.jsonl" -type f 2>/dev/null | head -1)
if [ -z "$NATIVE_FILE" ]; then
  echo "{}"
  exit 0
fi

# Aggregate token usage from all assistant entries in the native session
SNAPSHOT=$(grep '"type":"assistant"' "$NATIVE_FILE" 2>/dev/null | jq -sc --arg sid "$SESSION_ID" '
  if length == 0 then null else

  (last.message.model // "unknown") as $model |
  (if ($model | test("haiku"; "i")) then {in: 1, out: 5, cr: 0.10, cw: 1.25}
   elif ($model | test("sonnet"; "i")) then {in: 3, out: 15, cr: 0.30, cw: 3.75}
   else {in: 5, out: 25, cr: 0.50, cw: 6.25} end) as $prices |

  ([.[].message.usage.input_tokens // 0] | add) as $input |
  ([.[].message.usage.output_tokens // 0] | add) as $output |
  ([.[].message.usage.cache_read_input_tokens // 0] | add) as $cache_read |
  ([.[].message.usage.cache_creation_input_tokens // 0] | add) as $cache_write |

  # Cost calculation (per million tokens)
  (($input * $prices.in + $output * $prices.out + $cache_read * $prices.cr + $cache_write * $prices.cw) / 1000000) as $cost |

  # Duration from first to last timestamp (strip milliseconds for fromdateiso8601)
  (first.timestamp // "" | sub("\\.[0-9]+Z$"; "Z")) as $first_ts |
  (last.timestamp // "" | sub("\\.[0-9]+Z$"; "Z")) as $last_ts |
  (if ($first_ts | length) > 0 and ($last_ts | length) > 0
   then (($last_ts | fromdateiso8601) - ($first_ts | fromdateiso8601))
   else 0 end) as $duration_secs |

  # Context: last entry usage for current window estimate
  (last.message.usage.input_tokens // 0) as $last_input |
  (last.message.usage.cache_read_input_tokens // 0) as $last_cache_read |
  (last.message.usage.cache_creation_input_tokens // 0) as $last_cache_write |
  (last.message.usage.output_tokens // 0) as $last_output |
  ($last_input + $last_cache_read + $last_cache_write + $last_output) as $last_total |
  (if $last_total > 0 then (($last_total * 100) / 200000 | floor) else 0 end) as $ctx_pct |

  {
    type: "snapshot",
    timestamp: (now | todate),
    session_id: $sid,
    total_cost_usd: ($cost * 10000 | round / 10000),
    total_input_tokens: ($input + $cache_read),
    total_output_tokens: $output,
    cache_read_tokens: $cache_read,
    cache_write_tokens: $cache_write,
    context_used_pct: $ctx_pct,
    context_window_size: 200000,
    total_duration_ms: ($duration_secs * 1000),
    total_api_duration_ms: 0,
    total_lines_added: 0,
    total_lines_removed: 0,
    model: $model
  }

  end
' 2>/dev/null)

if [ -z "$SNAPSHOT" ] || [ "$SNAPSHOT" = "null" ]; then
  echo "{}"
  exit 0
fi

# Only write if cost changed (avoid duplicate snapshots on repeated tool calls)
LAST_SNAP_COST=$(grep '"type":"snapshot"' "$LOG_FILE" 2>/dev/null | tail -1 | jq -r '.total_cost_usd // 0' 2>/dev/null || echo "0")
NEW_COST=$(echo "$SNAPSHOT" | jq -r '.total_cost_usd // 0')

if [ "$NEW_COST" != "$LAST_SNAP_COST" ]; then
  echo "$SNAPSHOT" >> "$LOG_FILE"
fi

echo "{}"
