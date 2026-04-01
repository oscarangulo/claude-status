#!/bin/bash
# claude-status: Smart cost guardian for Claude Code
# Generates snapshots, checks budget, detects anomalies, watches context.
# Outputs additionalContext alerts that Claude sees and acts on.
# Works in both terminal CLI and VS Code extension.

set -euo pipefail

INPUT=$(cat)
DATA_DIR="${CLAUDE_STATUS_DIR:-$HOME/.claude-status}"
SESSION_DIR="$DATA_DIR/sessions"
CLAUDE_DIR="$HOME/.claude/projects"
BUDGET_FILE="$DATA_DIR/budget.json"
ALERTS_FILE="$DATA_DIR/alerts-sent.json"

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

# --- Aggregate token usage from native session ---
SNAPSHOT=$(grep '"type":"assistant"' "$NATIVE_FILE" 2>/dev/null | jq -sc --arg sid "$SESSION_ID" '
  if length == 0 then null else

  (last.message.model // "unknown") as $model |
  (if ($model | test("haiku"; "i")) then {in: 1, out: 5, cr: 0.10, cw: 1.25}
   elif ($model | test("sonnet"; "i")) then {in: 3, out: 15, cr: 0.30, cw: 3.75}
   else {in: 5, out: 25, cr: 0.50, cw: 6.25} end) as $prices |

  (if ($model | test("haiku"; "i")) then 200000
   elif ($model | test("sonnet"; "i")) then 200000
   else 1000000 end) as $ctx_window |

  ([.[].message.usage.input_tokens // 0] | add) as $input |
  ([.[].message.usage.output_tokens // 0] | add) as $output |
  ([.[].message.usage.cache_read_input_tokens // 0] | add) as $cache_read |
  ([.[].message.usage.cache_creation_input_tokens // 0] | add) as $cache_write |

  (($input * $prices.in + $output * $prices.out + $cache_read * $prices.cr + $cache_write * $prices.cw) / 1000000) as $cost |

  (first.timestamp // "" | sub("\\.[0-9]+Z$"; "Z")) as $first_ts |
  (last.timestamp // "" | sub("\\.[0-9]+Z$"; "Z")) as $last_ts |
  (if ($first_ts | length) > 0 and ($last_ts | length) > 0
   then (($last_ts | fromdateiso8601) - ($first_ts | fromdateiso8601))
   else 0 end) as $duration_secs |

  (last.message.usage.input_tokens // 0) as $last_input |
  (last.message.usage.cache_read_input_tokens // 0) as $last_cache_read |
  (last.message.usage.cache_creation_input_tokens // 0) as $last_cache_write |
  (last.message.usage.output_tokens // 0) as $last_output |
  ($last_input + $last_cache_read + $last_cache_write + $last_output) as $last_total |
  (if $last_total > 0 then (($last_total * 100) / $ctx_window | floor) else 0 end) as $ctx_pct |

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
    context_window_size: $ctx_window,
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

# Only write if cost changed
LAST_SNAP_COST=$(grep '"type":"snapshot"' "$LOG_FILE" 2>/dev/null | tail -1 | jq -r '.total_cost_usd // 0' 2>/dev/null || echo "0")
NEW_COST=$(echo "$SNAPSHOT" | jq -r '.total_cost_usd // 0')
NEW_CTX=$(echo "$SNAPSHOT" | jq -r '.context_used_pct // 0')

if [ "$NEW_COST" != "$LAST_SNAP_COST" ]; then
  echo "$SNAPSHOT" >> "$LOG_FILE"
fi

# ===================================================================
# SMART ALERTS — output additionalContext for Claude to see
# ===================================================================

ALERTS=""

# Helper: check if alert was already sent for this session + type
alert_sent() {
  local key="$1"
  if [ -f "$ALERTS_FILE" ]; then
    jq -e --arg k "${SESSION_ID}:${key}" '.[$k] // false' "$ALERTS_FILE" >/dev/null 2>&1
  else
    return 1
  fi
}

# Helper: mark alert as sent
mark_alert() {
  local key="$1"
  if [ -f "$ALERTS_FILE" ]; then
    local tmp=$(jq --arg k "${SESSION_ID}:${key}" '.[$k] = true' "$ALERTS_FILE" 2>/dev/null)
    echo "$tmp" > "$ALERTS_FILE"
  else
    echo "{\"${SESSION_ID}:${key}\": true}" > "$ALERTS_FILE"
  fi
}

add_alert() {
  if [ -z "$ALERTS" ]; then
    ALERTS="$1"
  else
    ALERTS="${ALERTS} | $1"
  fi
}

# --- 1. BUDGET ALERTS ---
if [ -f "$BUDGET_FILE" ]; then
  DAILY_LIMIT=$(jq -r '.daily_limit // 0' "$BUDGET_FILE" 2>/dev/null)
  SESSION_LIMIT=$(jq -r '.session_limit // 0' "$BUDGET_FILE" 2>/dev/null)

  if [ "$DAILY_LIMIT" != "0" ] && [ "$DAILY_LIMIT" != "null" ]; then
    # Sum cost from all sessions today
    TODAY=$(date -u +"%Y-%m-%d")
    DAILY_COST=0
    for sf in "$SESSION_DIR"/*.jsonl; do
      [ -f "$sf" ] || continue
      LAST=$(grep '"type":"snapshot"' "$sf" 2>/dev/null | tail -1 || true)
      [ -z "$LAST" ] && continue
      TS=$(echo "$LAST" | jq -r '.timestamp // ""' 2>/dev/null)
      case "$TS" in ${TODAY}*) ;; *) continue ;; esac
      C=$(echo "$LAST" | jq -r '.total_cost_usd // 0' 2>/dev/null)
      DAILY_COST=$(echo "$DAILY_COST + $C" | bc 2>/dev/null || echo "$DAILY_COST")
    done

    PCT=$(echo "scale=0; $DAILY_COST * 100 / $DAILY_LIMIT" | bc 2>/dev/null || echo "0")

    if [ "$PCT" -ge 100 ] && ! alert_sent "budget_100"; then
      add_alert "BUDGET EXCEEDED: Daily spend \$$(printf '%.2f' "$DAILY_COST") has passed your \$${DAILY_LIMIT} limit. Stop or continue at your own risk."
      mark_alert "budget_100"
    elif [ "$PCT" -ge 80 ] && ! alert_sent "budget_80"; then
      add_alert "BUDGET WARNING: Daily spend \$$(printf '%.2f' "$DAILY_COST") is ${PCT}% of your \$${DAILY_LIMIT} daily limit."
      mark_alert "budget_80"
    elif [ "$PCT" -ge 50 ] && ! alert_sent "budget_50"; then
      add_alert "Budget update: \$$(printf '%.2f' "$DAILY_COST") spent today (${PCT}% of \$${DAILY_LIMIT} limit)."
      mark_alert "budget_50"
    fi
  fi

  if [ "$SESSION_LIMIT" != "0" ] && [ "$SESSION_LIMIT" != "null" ]; then
    S_PCT=$(echo "scale=0; $NEW_COST * 100 / $SESSION_LIMIT" | bc 2>/dev/null || echo "0")
    if [ "$S_PCT" -ge 100 ] && ! alert_sent "session_100"; then
      add_alert "SESSION BUDGET EXCEEDED: \$${NEW_COST} spent, limit is \$${SESSION_LIMIT}."
      mark_alert "session_100"
    elif [ "$S_PCT" -ge 80 ] && ! alert_sent "session_80"; then
      add_alert "Session spend \$${NEW_COST} is ${S_PCT}% of \$${SESSION_LIMIT} session limit."
      mark_alert "session_80"
    fi
  fi
fi

# --- 2. CONTEXT WATCHDOG ---
if [ "$NEW_CTX" -ge 90 ] && ! alert_sent "ctx_90"; then
  add_alert "CONTEXT CRITICAL (${NEW_CTX}%): Use /compact NOW or risk losing conversation history."
  mark_alert "ctx_90"
elif [ "$NEW_CTX" -ge 80 ] && ! alert_sent "ctx_80"; then
  add_alert "Context window at ${NEW_CTX}%. Consider using /compact soon."
  mark_alert "ctx_80"
fi

# --- 3. COST ANOMALY (session cost > $5 per 10 minutes) ---
DURATION_MS=$(echo "$SNAPSHOT" | jq -r '.total_duration_ms // 0')
if [ "$DURATION_MS" -gt 0 ]; then
  BURN=$(echo "scale=4; $NEW_COST / ($DURATION_MS / 60000)" | bc 2>/dev/null || echo "0")
  if [ "$(echo "$BURN > 0.50" | bc 2>/dev/null)" = "1" ] && ! alert_sent "burn_high"; then
    BURN_DISPLAY=$(printf '%.2f' "$BURN")
    add_alert "High burn rate: \$${BURN_DISPLAY}/min. Consider breaking tasks into smaller pieces."
    mark_alert "burn_high"
  fi
fi

# --- 4. EXPENSIVE LOOP DETECTION ---
# Detect 3+ consecutive failed tool calls (same tool, error results)
TOOL_NAME=$(echo "$INPUT" | jq -r '.tool_name // ""' 2>/dev/null || echo "")
if [ -n "$TOOL_NAME" ] && [ "$TOOL_NAME" != "null" ]; then
  LOOP_FILE="$DATA_DIR/loop-${SESSION_ID}.json"
  TOOL_ERROR=$(echo "$INPUT" | jq -r '.tool_result.is_error // false' 2>/dev/null || echo "false")

  if [ "$TOOL_ERROR" = "true" ]; then
    # Track consecutive failures
    if [ -f "$LOOP_FILE" ]; then
      PREV_TOOL=$(jq -r '.tool // ""' "$LOOP_FILE" 2>/dev/null)
      PREV_COUNT=$(jq -r '.count // 0' "$LOOP_FILE" 2>/dev/null)
      if [ "$PREV_TOOL" = "$TOOL_NAME" ]; then
        NEW_COUNT=$((PREV_COUNT + 1))
      else
        NEW_COUNT=1
      fi
    else
      NEW_COUNT=1
    fi
    echo "{\"tool\":\"$TOOL_NAME\",\"count\":$NEW_COUNT}" > "$LOOP_FILE"

    if [ "$NEW_COUNT" -ge 3 ] && ! alert_sent "loop_${TOOL_NAME}"; then
      add_alert "Loop detected: ${NEW_COUNT} failed ${TOOL_NAME} calls in a row. Consider explaining the issue instead of retrying."
      mark_alert "loop_${TOOL_NAME}"
    fi
  else
    # Success resets the counter
    if [ -f "$LOOP_FILE" ]; then
      rm -f "$LOOP_FILE"
    fi
  fi
fi

# --- 5. SESSION COST COMPARISON ---
# Alert when current session costs 2x the average of past sessions
if ! alert_sent "cost_high_vs_avg"; then
  AVG_DATA=$(for sf in "$SESSION_DIR"/*.jsonl; do
    [ -f "$sf" ] || continue
    [ "$sf" = "$LOG_FILE" ] && continue
    grep '"type":"snapshot"' "$sf" 2>/dev/null | tail -1 | jq -r '.total_cost_usd // 0' 2>/dev/null
  done | jq -s 'if length >= 3 then {avg: (add / length), n: length} else null end' 2>/dev/null)

  if [ -n "$AVG_DATA" ] && [ "$AVG_DATA" != "null" ]; then
    AVG_COST=$(echo "$AVG_DATA" | jq -r '.avg')
    if [ "$(echo "$AVG_COST > 0" | bc 2>/dev/null)" = "1" ]; then
      RATIO=$(echo "scale=1; $NEW_COST / $AVG_COST" | bc 2>/dev/null || echo "0")
      if [ "$(echo "$RATIO >= 2.0" | bc 2>/dev/null)" = "1" ]; then
        AVG_DISPLAY=$(printf '%.2f' "$AVG_COST")
        COST_DISPLAY=$(printf '%.2f' "$NEW_COST")
        add_alert "Expensive session: \$${COST_DISPLAY} is ${RATIO}x your average (\$${AVG_DISPLAY}). Consider splitting into smaller tasks."
        mark_alert "cost_high_vs_avg"
      fi
    fi
  fi
fi

# --- 6. MODEL DOWNGRADE SUGGESTION ---
# If using Opus and last 5 tool calls are all lightweight (Read, Grep, Glob, LS)
CURRENT_MODEL=$(echo "$SNAPSHOT" | jq -r '.model // ""')
if echo "$CURRENT_MODEL" | grep -qi "opus" && ! alert_sent "model_suggest"; then
  if [ -n "$NATIVE_FILE" ]; then
    RECENT_TOOLS=$(tail -20 "$NATIVE_FILE" 2>/dev/null | grep '"tool_use"' | jq -r '.message.content[]?.name // empty' 2>/dev/null | tail -5 || true)
    if [ -n "$RECENT_TOOLS" ]; then
      LIGHT_STREAK=$(echo "$RECENT_TOOLS" | grep -cE '^(Read|Grep|Glob|LS|View|ListDir)$' || echo "0")
      TOTAL_RECENT=$(echo "$RECENT_TOOLS" | grep -c '.' || echo "0")
    else
      LIGHT_STREAK=0
      TOTAL_RECENT=0
    fi
    if [ "$TOTAL_RECENT" -ge 5 ] && [ "$LIGHT_STREAK" -eq "$TOTAL_RECENT" ]; then
      add_alert "Light tasks detected (reads/searches). Consider using Sonnet for this work to save ~70% on costs."
      mark_alert "model_suggest"
    fi
  fi
fi

# --- 7. IDLE CONTEXT WARNING ---
# Context > 70% and last native entry was > 10 minutes ago
if [ "$NEW_CTX" -ge 70 ] && ! alert_sent "idle_ctx"; then
  if [ -n "$NATIVE_FILE" ]; then
    # Get the last entry's timestamp from native session, strip milliseconds
    LAST_NATIVE_TS=$(tail -1 "$NATIVE_FILE" 2>/dev/null | jq -r '.timestamp // ""' 2>/dev/null | sed 's/\.[0-9]*Z$/Z/' || echo "")
    if [ -n "$LAST_NATIVE_TS" ] && [ "$LAST_NATIVE_TS" != "null" ]; then
      LAST_EPOCH=$(date -jf "%Y-%m-%dT%H:%M:%SZ" "$LAST_NATIVE_TS" +%s 2>/dev/null || date -d "$LAST_NATIVE_TS" +%s 2>/dev/null || echo "0")
      NOW_EPOCH=$(date +%s)
      if [ "$LAST_EPOCH" -gt 0 ]; then
        IDLE_SECS=$((NOW_EPOCH - LAST_EPOCH))
        if [ "$IDLE_SECS" -gt 600 ]; then
          IDLE_MIN=$((IDLE_SECS / 60))
          add_alert "Context at ${NEW_CTX}% with ${IDLE_MIN}min idle. Consider starting a new session to save tokens."
          mark_alert "idle_ctx"
        fi
      fi
    fi
  fi
fi

# --- OUTPUT ---
if [ -n "$ALERTS" ]; then
  jq -cn --arg ctx "[claude-status] $ALERTS" '{
    hookSpecificOutput: {
      hookEventName: "PostToolUse",
      additionalContext: $ctx
    }
  }'
else
  echo "{}"
fi
