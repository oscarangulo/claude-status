#!/bin/bash
# claude-status: Rich status line for Claude Code
#
# Shows real-time cost, tokens, cache efficiency, context usage,
# burn rate, cache savings, and current task — with ANSI colors.
# Multi-line: line 1 = cost & tokens, line 2 = context & efficiency, line 3 = task

set -euo pipefail

INPUT=$(cat)
DATA_DIR="${CLAUDE_STATUS_DIR:-$HOME/.claude-status}"
SESSION_DIR="$DATA_DIR/sessions"

# --- ANSI colors ---
RST=$'\033[0m'
BOLD=$'\033[1m'
DIM=$'\033[2m'
GREEN=$'\033[32m'
YELLOW=$'\033[33m'
RED=$'\033[31m'
CYAN=$'\033[36m'
MAGENTA=$'\033[35m'
WHITE=$'\033[97m'
BLUE=$'\033[34m'

# Single jq call to extract everything
eval "$(echo "$INPUT" | jq -r '
  @sh "SESSION_ID=\(.session_id // "unknown")",
  @sh "TOTAL_COST=\(.cost.total_cost_usd // 0)",
  @sh "TOTAL_DURATION=\(.cost.total_duration_ms // 0)",
  @sh "API_DURATION=\(.cost.total_api_duration_ms // 0)",
  @sh "LINES_ADDED=\(.cost.total_lines_added // 0)",
  @sh "LINES_REMOVED=\(.cost.total_lines_removed // 0)",
  @sh "TOTAL_INPUT=\(.context_window.total_input_tokens // 0)",
  @sh "TOTAL_OUTPUT=\(.context_window.total_output_tokens // 0)",
  @sh "CACHE_READ=\(.context_window.current_usage.cache_read_input_tokens // 0)",
  @sh "CACHE_WRITE=\(.context_window.current_usage.cache_creation_input_tokens // 0)",
  @sh "CTX_SIZE=\(.context_window.context_window_size // 0)",
  @sh "CTX_PCT=\(.context_window.used_percentage // 0)",
  @sh "INPUT_TOK=\(.context_window.current_usage.input_tokens // 0)",
  @sh "OUTPUT_TOK=\(.context_window.current_usage.output_tokens // 0)",
  @sh "MODEL=\(.model.display_name // "unknown")"
' | tr ',' '\n')"

# --- Log snapshot to JSONL ---
mkdir -p "$SESSION_DIR"
TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
LOG_FILE="$SESSION_DIR/${SESSION_ID}.jsonl"

jq -cn \
  --arg type "snapshot" \
  --arg timestamp "$TIMESTAMP" \
  --arg session_id "$SESSION_ID" \
  --arg model "$MODEL" \
  --argjson total_cost_usd "$TOTAL_COST" \
  --argjson total_input_tokens "$TOTAL_INPUT" \
  --argjson total_output_tokens "$TOTAL_OUTPUT" \
  --argjson cache_read_tokens "$CACHE_READ" \
  --argjson cache_write_tokens "$CACHE_WRITE" \
  --argjson context_used_pct "$CTX_PCT" \
  --argjson context_window_size "$CTX_SIZE" \
  --argjson total_duration_ms "$TOTAL_DURATION" \
  --argjson total_api_duration_ms "$API_DURATION" \
  --argjson total_lines_added "$LINES_ADDED" \
  --argjson total_lines_removed "$LINES_REMOVED" \
  '{
    type: $type,
    timestamp: $timestamp,
    session_id: $session_id,
    total_cost_usd: $total_cost_usd,
    total_input_tokens: $total_input_tokens,
    total_output_tokens: $total_output_tokens,
    cache_read_tokens: $cache_read_tokens,
    cache_write_tokens: $cache_write_tokens,
    context_used_pct: $context_used_pct,
    context_window_size: $context_window_size,
    total_duration_ms: $total_duration_ms,
    total_api_duration_ms: $total_api_duration_ms,
    total_lines_added: $total_lines_added,
    total_lines_removed: $total_lines_removed,
    model: $model
  }' >> "$LOG_FILE"

# --- Format tokens ---
format_tok() {
  local n=$1
  if [ "$n" -ge 1000000 ]; then
    awk "BEGIN{printf \"%.1fM\", $n / 1000000}"
  elif [ "$n" -ge 1000 ]; then
    awk "BEGIN{printf \"%.1fK\", $n / 1000}"
  else
    printf "%d" "$n"
  fi
}

# --- Cache hit rate ---
TOTAL_IN=$((INPUT_TOK + CACHE_READ))
if [ "$TOTAL_IN" -gt 0 ]; then
  CACHE_HIT=$(awk "BEGIN{printf \"%d\", $CACHE_READ * 100 / $TOTAL_IN}")
else
  CACHE_HIT=0
fi

if [ "$CACHE_HIT" -ge 50 ]; then
  CACHE_COLOR=$GREEN
elif [ "$CACHE_HIT" -ge 20 ]; then
  CACHE_COLOR=$YELLOW
else
  CACHE_COLOR=$RED
fi

# --- Pricing per model (per token) ---
# Defaults to Opus pricing; detect model for accuracy
case "$MODEL" in
  *Haiku*)
    IN_PRICE="0.000001"   # $1/MTok
    OUT_PRICE="0.000005"  # $5/MTok
    CACHE_R_PRICE="0.0000001"   # $0.10/MTok
    CACHE_W_PRICE="0.00000125"  # $1.25/MTok
    ;;
  *Sonnet*)
    IN_PRICE="0.000003"   # $3/MTok
    OUT_PRICE="0.000015"  # $15/MTok
    CACHE_R_PRICE="0.0000003"   # $0.30/MTok
    CACHE_W_PRICE="0.00000375"  # $3.75/MTok
    ;;
  *) # Opus or unknown
    IN_PRICE="0.000005"   # $5/MTok
    OUT_PRICE="0.000025"  # $25/MTok
    CACHE_R_PRICE="0.0000005"   # $0.50/MTok
    CACHE_W_PRICE="0.00000625"  # $6.25/MTok
    ;;
esac

# --- Cost breakdown by type ---
INPUT_COST=$(awk "BEGIN{printf \"%.6f\", $INPUT_TOK * $IN_PRICE}")
OUTPUT_COST=$(awk "BEGIN{printf \"%.6f\", $OUTPUT_TOK * $OUT_PRICE}")
CACHE_R_COST=$(awk "BEGIN{printf \"%.6f\", $CACHE_READ * $CACHE_R_PRICE}")
CACHE_W_COST=$(awk "BEGIN{printf \"%.6f\", $CACHE_WRITE * $CACHE_W_PRICE}")

# Cache savings = what you would have paid at full input price minus what you actually paid
CACHE_SAVINGS=$(awk "BEGIN{printf \"%.6f\", ($CACHE_READ * $IN_PRICE) - ($CACHE_READ * $CACHE_R_PRICE)}")
CACHE_SAVINGS_DISPLAY=$(printf "%.4f" "$CACHE_SAVINGS")

# --- Burn rate ($/min) ---
BURN_RATE="0"
if [ "$TOTAL_DURATION" -gt 60000 ]; then
  MINUTES=$(awk "BEGIN{printf \"%.2f\", $TOTAL_DURATION / 60000}")
  BURN_RATE=$(awk "BEGIN{printf \"%.4f\", $TOTAL_COST / $MINUTES}")
fi

# --- Duration ---
if [ "$TOTAL_DURATION" -gt 0 ]; then
  SECS=$((TOTAL_DURATION / 1000))
  if [ "$SECS" -ge 3600 ]; then
    DURATION="$(($SECS / 3600))h$(($SECS % 3600 / 60))m"
  elif [ "$SECS" -ge 60 ]; then
    DURATION="$(($SECS / 60))m$(($SECS % 60))s"
  else
    DURATION="${SECS}s"
  fi
else
  DURATION="0s"
fi

# --- Context bar ---
BAR_LEN=10
FILLED=$((CTX_PCT * BAR_LEN / 100))
if [ "$FILLED" -gt "$BAR_LEN" ]; then FILLED=$BAR_LEN; fi
EMPTY=$((BAR_LEN - FILLED))

if [ "$CTX_PCT" -ge 80 ]; then
  BAR_COLOR=$RED
elif [ "$CTX_PCT" -ge 60 ]; then
  BAR_COLOR=$YELLOW
else
  BAR_COLOR=$GREEN
fi

FILLED_BAR=""
EMPTY_BAR=""
for ((i=0; i<FILLED; i++)); do FILLED_BAR="${FILLED_BAR}#"; done
for ((i=0; i<EMPTY; i++)); do EMPTY_BAR="${EMPTY_BAR}-"; done
CTX_BAR="${BAR_COLOR}${FILLED_BAR}${DIM}${EMPTY_BAR}${RST}"

CTX_WARN=""
if [ "$CTX_PCT" -ge 80 ]; then
  CTX_WARN=" ${RED}!!${RST}"
fi

# --- Cost color ---
COST_VAL=$(printf "%.4f" "$TOTAL_COST")
if [ "$(awk "BEGIN{print ($TOTAL_COST > 1) ? 1 : 0}")" -eq 1 ]; then
  COST_DISPLAY="${RED}${BOLD}\$${COST_VAL}${RST}"
elif [ "$(awk "BEGIN{print ($TOTAL_COST > 0.5) ? 1 : 0}")" -eq 1 ]; then
  COST_DISPLAY="${YELLOW}\$${COST_VAL}${RST}"
else
  COST_DISPLAY="${GREEN}\$${COST_VAL}${RST}"
fi

# --- Lines changed ---
LINES_INFO=""
if [ "$LINES_ADDED" -gt 0 ] || [ "$LINES_REMOVED" -gt 0 ]; then
  LINES_INFO=" ${DIM}|${RST} ${GREEN}${LINES_ADDED} added${RST}${DIM},${RST} ${RED}${LINES_REMOVED} removed${RST}"
fi

# --- Burn rate display ---
BURN_DISPLAY=""
if [ "$(awk "BEGIN{print ($BURN_RATE > 0) ? 1 : 0}")" -eq 1 ]; then
  BURN_VAL=$(printf "%.3f" "$BURN_RATE")
  if [ "$(awk "BEGIN{print ($BURN_RATE > 0.1) ? 1 : 0}")" -eq 1 ]; then
    BURN_DISPLAY=" ${DIM}(${RST}${RED}\$${BURN_VAL}/min${RST}${DIM})${RST}"
  elif [ "$(awk "BEGIN{print ($BURN_RATE > 0.05) ? 1 : 0}")" -eq 1 ]; then
    BURN_DISPLAY=" ${DIM}(${RST}${YELLOW}\$${BURN_VAL}/min${RST}${DIM})${RST}"
  else
    BURN_DISPLAY=" ${DIM}(\$${BURN_VAL}/min)${RST}"
  fi
fi

# --- Cache savings display ---
SAVINGS_DISPLAY=""
if [ "$(awk "BEGIN{print ($CACHE_SAVINGS > 0.001) ? 1 : 0}")" -eq 1 ]; then
  SAVINGS_DISPLAY=" ${DIM}|${RST} ${GREEN}Cache saved \$${CACHE_SAVINGS_DISPLAY}${RST}"
fi

# --- Current task ---
TASK_LINE=""
if [ -f "$LOG_FILE" ]; then
  LAST_STARTED=$(grep '"event":"task_started"' "$LOG_FILE" 2>/dev/null | tail -1 || echo "")
  if [ -n "$LAST_STARTED" ]; then
    TASK_SUBJECT=$(echo "$LAST_STARTED" | jq -r '.task_subject // ""')
    TASK_COST_START=$(echo "$LAST_STARTED" | jq -r '.cost_snapshot_usd // 0')
    TASK_ID=$(echo "$LAST_STARTED" | jq -r '.task_id // ""')
    COMPLETED=$(grep "\"task_id\":\"$TASK_ID\".*\"event\":\"task_completed\"" "$LOG_FILE" 2>/dev/null | tail -1 || echo "")

    if [ -z "$COMPLETED" ]; then
      TASK_DELTA=$(awk "BEGIN{printf \"%.4f\", $TOTAL_COST - $TASK_COST_START}")
      if [ ${#TASK_SUBJECT} -gt 35 ]; then
        TASK_SUBJECT="${TASK_SUBJECT:0:32}..."
      fi
      TASK_LINE="${MAGENTA}Working on: ${TASK_SUBJECT}${RST} ${CYAN}(\$${TASK_DELTA} so far)${RST}"
    fi
  fi
fi

# --- Line 1: Spent, speed, time, code ---
TOTAL_TOK=$((TOTAL_INPUT + TOTAL_OUTPUT))
printf "%b" "Spent ${COST_DISPLAY}${BURN_DISPLAY} ${DIM}|${RST} ${WHITE}$(format_tok $TOTAL_TOK) tokens${RST} ${DIM}(${RST}$(format_tok $INPUT_TOK) read${DIM},${RST} $(format_tok $OUTPUT_TOK) written${DIM})${RST} ${DIM}|${RST} ${DIM}${DURATION}${RST}${LINES_INFO}"
echo

# --- Line 2: Memory, cache reuse, savings ---
printf "%b" "Memory [${CTX_BAR}] ${BAR_COLOR}${CTX_PCT}%${RST}${CTX_WARN} ${DIM}|${RST} ${CACHE_COLOR}${CACHE_HIT}% reused from cache${RST}${SAVINGS_DISPLAY}"
echo

# --- Line 3: Current task + subagents ---
AGENT_INFO=""
if [ -f "$LOG_FILE" ]; then
  AGENT_COUNT=$(grep -c '"type":"subagent_event"' "$LOG_FILE" 2>/dev/null || echo "0")
  if [ "$AGENT_COUNT" -gt 0 ]; then
    AGENT_COST=$(grep '"type":"subagent_event"' "$LOG_FILE" 2>/dev/null | jq -s '[.[].cost_usd] | add' 2>/dev/null || echo "0")
    AGENT_COST_DISPLAY=$(printf "%.4f" "$AGENT_COST")
    AGENT_INFO="${DIM}|${RST} ${CYAN}${AGENT_COUNT} agents (\$${AGENT_COST_DISPLAY})${RST}"
  fi
fi

if [ -n "$TASK_LINE" ] || [ -n "$AGENT_INFO" ]; then
  printf "%b" "${TASK_LINE:+$TASK_LINE }${AGENT_INFO}"
  echo
fi
