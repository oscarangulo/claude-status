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

printf '{"type":"snapshot","timestamp":"%s","session_id":"%s","total_cost_usd":%s,"total_input_tokens":%s,"total_output_tokens":%s,"cache_read_tokens":%s,"cache_write_tokens":%s,"context_used_pct":%s,"context_window_size":%s,"total_duration_ms":%s,"total_api_duration_ms":%s,"total_lines_added":%s,"total_lines_removed":%s,"model":"%s"}\n' \
  "$TIMESTAMP" "$SESSION_ID" "$TOTAL_COST" "$TOTAL_INPUT" "$TOTAL_OUTPUT" \
  "$CACHE_READ" "$CACHE_WRITE" "$CTX_PCT" "$CTX_SIZE" "$TOTAL_DURATION" \
  "$API_DURATION" "$LINES_ADDED" "$LINES_REMOVED" "$MODEL" >> "$LOG_FILE"

# --- Format tokens ---
format_tok() {
  local n=$1
  if [ "$n" -ge 1000000 ]; then
    printf "%.1fM" "$(echo "scale=1; $n / 1000000" | bc)"
  elif [ "$n" -ge 1000 ]; then
    printf "%.1fK" "$(echo "scale=1; $n / 1000" | bc)"
  else
    printf "%d" "$n"
  fi
}

# --- Cache hit rate ---
TOTAL_IN=$((INPUT_TOK + CACHE_READ))
if [ "$TOTAL_IN" -gt 0 ]; then
  CACHE_HIT=$(echo "scale=0; $CACHE_READ * 100 / $TOTAL_IN" | bc)
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
INPUT_COST=$(echo "scale=6; $INPUT_TOK * $IN_PRICE" | bc)
OUTPUT_COST=$(echo "scale=6; $OUTPUT_TOK * $OUT_PRICE" | bc)
CACHE_R_COST=$(echo "scale=6; $CACHE_READ * $CACHE_R_PRICE" | bc)
CACHE_W_COST=$(echo "scale=6; $CACHE_WRITE * $CACHE_W_PRICE" | bc)

# Cache savings = what you would have paid at full input price minus what you actually paid
CACHE_SAVINGS=$(echo "scale=6; ($CACHE_READ * $IN_PRICE) - ($CACHE_READ * $CACHE_R_PRICE)" | bc)
CACHE_SAVINGS_DISPLAY=$(printf "%.4f" "$CACHE_SAVINGS")

# --- Burn rate ($/min) ---
BURN_RATE="0"
if [ "$TOTAL_DURATION" -gt 60000 ]; then
  MINUTES=$(echo "scale=2; $TOTAL_DURATION / 60000" | bc)
  BURN_RATE=$(echo "scale=4; $TOTAL_COST / $MINUTES" | bc)
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
if [ "$(echo "$TOTAL_COST > 1" | bc)" -eq 1 ]; then
  COST_DISPLAY="${RED}${BOLD}\$${COST_VAL}${RST}"
elif [ "$(echo "$TOTAL_COST > 0.5" | bc)" -eq 1 ]; then
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
if [ "$(echo "$BURN_RATE > 0" | bc)" -eq 1 ]; then
  BURN_VAL=$(printf "%.3f" "$BURN_RATE")
  if [ "$(echo "$BURN_RATE > 0.1" | bc)" -eq 1 ]; then
    BURN_DISPLAY=" ${DIM}(${RST}${RED}\$${BURN_VAL}/min${RST}${DIM})${RST}"
  elif [ "$(echo "$BURN_RATE > 0.05" | bc)" -eq 1 ]; then
    BURN_DISPLAY=" ${DIM}(${RST}${YELLOW}\$${BURN_VAL}/min${RST}${DIM})${RST}"
  else
    BURN_DISPLAY=" ${DIM}(\$${BURN_VAL}/min)${RST}"
  fi
fi

# --- Cache savings display ---
SAVINGS_DISPLAY=""
if [ "$(echo "$CACHE_SAVINGS > 0.001" | bc)" -eq 1 ]; then
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
      TASK_DELTA=$(printf "%.4f" "$(echo "scale=4; $TOTAL_COST - $TASK_COST_START" | bc)")
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

# --- Line 3: Current task (if any) ---
if [ -n "$TASK_LINE" ]; then
  printf "%b" "$TASK_LINE"
  echo
fi
