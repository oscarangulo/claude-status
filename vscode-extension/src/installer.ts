import * as fs from 'fs';
import * as path from 'path';
import * as os from 'os';
import * as vscode from 'vscode';

const STATUS_LINE_SCRIPT = `#!/bin/bash
# claude-status: Status line hook for Claude Code
# Auto-installed by the Claude Status Monitor VS Code extension

set -euo pipefail

INPUT=$(cat)
DATA_DIR="\${CLAUDE_STATUS_DIR:-$HOME/.claude-status}"
SESSION_DIR="$DATA_DIR/sessions"
RUN_ID=$(date -u +"%Y%m%dT%H%M%SZ")
RUN_ID=$(date -u +"%Y%m%dT%H%M%SZ")

eval "$(echo "$INPUT" | jq -r '
  @sh "SESSION_ID=\\(.session_id // "unknown")",
  @sh "TOTAL_COST=\\(.cost.total_cost_usd // 0)",
  @sh "TOTAL_DURATION=\\(.cost.total_duration_ms // 0)",
  @sh "API_DURATION=\\(.cost.total_api_duration_ms // 0)",
  @sh "LINES_ADDED=\\(.cost.total_lines_added // 0)",
  @sh "LINES_REMOVED=\\(.cost.total_lines_removed // 0)",
  @sh "TOTAL_INPUT=\\(.context_window.total_input_tokens // 0)",
  @sh "TOTAL_OUTPUT=\\(.context_window.total_output_tokens // 0)",
  @sh "CACHE_READ=\\(.context_window.current_usage.cache_read_input_tokens // 0)",
  @sh "CACHE_WRITE=\\(.context_window.current_usage.cache_creation_input_tokens // 0)",
  @sh "CTX_SIZE=\\(.context_window.context_window_size // 0)",
  @sh "CTX_PCT=\\(.context_window.used_percentage // 0)",
  @sh "INPUT_TOK=\\(.context_window.current_usage.input_tokens // 0)",
  @sh "OUTPUT_TOK=\\(.context_window.current_usage.output_tokens // 0)",
  @sh "MODEL=\\(.model.display_name // "unknown")"
' | tr ',' '\\n')"

mkdir -p "$SESSION_DIR"
TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
LOG_FILE="$SESSION_DIR/\${SESSION_ID}.jsonl"

jq -cn \\
  --arg type "snapshot" \\
  --arg timestamp "$TIMESTAMP" \\
  --arg session_id "$SESSION_ID" \\
  --arg model "$MODEL" \\
  --argjson total_cost_usd "$TOTAL_COST" \\
  --argjson total_input_tokens "$TOTAL_INPUT" \\
  --argjson total_output_tokens "$TOTAL_OUTPUT" \\
  --argjson cache_read_tokens "$CACHE_READ" \\
  --argjson cache_write_tokens "$CACHE_WRITE" \\
  --argjson context_used_pct "$CTX_PCT" \\
  --argjson context_window_size "$CTX_SIZE" \\
  --argjson total_duration_ms "$TOTAL_DURATION" \\
  --argjson total_api_duration_ms "$API_DURATION" \\
  --argjson total_lines_added "$LINES_ADDED" \\
  --argjson total_lines_removed "$LINES_REMOVED" \\
  '{ \\
    type: $type, \\
    timestamp: $timestamp, \\
    session_id: $session_id, \\
    total_cost_usd: $total_cost_usd, \\
    total_input_tokens: $total_input_tokens, \\
    total_output_tokens: $total_output_tokens, \\
    cache_read_tokens: $cache_read_tokens, \\
    cache_write_tokens: $cache_write_tokens, \\
    context_used_pct: $context_used_pct, \\
    context_window_size: $context_window_size, \\
    total_duration_ms: $total_duration_ms, \\
    total_api_duration_ms: $total_api_duration_ms, \\
    total_lines_added: $total_lines_added, \\
    total_lines_removed: $total_lines_removed, \\
    model: $model \\
  }' >> "$LOG_FILE"

# Display in Claude Code terminal
TOTAL_TOK=$((TOTAL_INPUT + TOTAL_OUTPUT))
format_tok() {
  local n=$1
  if [ "$n" -ge 1000000 ]; then printf "%.1fM" "$(echo "scale=1; $n / 1000000" | bc)"
  elif [ "$n" -ge 1000 ]; then printf "%.1fK" "$(echo "scale=1; $n / 1000" | bc)"
  else printf "%d" "$n"; fi
}
printf "Spent \\$%.4f | %s tokens | %s" "$TOTAL_COST" "$(format_tok $TOTAL_TOK)" "$MODEL"
`;

const TASK_HOOK_SCRIPT = `#!/bin/bash
# claude-status: Task tracking hook for Claude Code
# Auto-installed by the Claude Status Monitor VS Code extension

set -euo pipefail

INPUT=$(cat)
DATA_DIR="\${CLAUDE_STATUS_DIR:-$HOME/.claude-status}"
SESSION_DIR="$DATA_DIR/sessions"

eval "$(echo "$INPUT" | jq -r '
  @sh "SESSION_ID=\\(.session_id // "unknown")",
  @sh "HOOK_EVENT=\\(.hook_event_name // "unknown")",
  @sh "TOOL_NAME=\\(.tool_name // "")"
' | tr ',' '\\n')"

TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
mkdir -p "$SESSION_DIR"
LOG_FILE="$SESSION_DIR/\${SESSION_ID}.jsonl"

COST_SNAP=0
TOKEN_SNAP=0
if [ -f "$LOG_FILE" ]; then
  LAST_SNAP=$(grep '"type":"snapshot"' "$LOG_FILE" | tail -1 2>/dev/null || echo "")
  if [ -n "$LAST_SNAP" ]; then
    eval "$(echo "$LAST_SNAP" | jq -r '
      @sh "COST_SNAP=\\(.total_cost_usd // 0)",
      @sh "S_INPUT_TOK=\\(.total_input_tokens // 0)",
      @sh "S_OUTPUT_TOK=\\(.total_output_tokens // 0)"
    ' | tr ',' '\\n')"
    TOKEN_SNAP=$((S_INPUT_TOK + S_OUTPUT_TOK))
  fi
fi

hash_string() {
  if command -v md5sum >/dev/null 2>&1; then echo -n "$1" | md5sum | cut -c1-8
  elif command -v md5 >/dev/null 2>&1; then echo -n "$1" | md5 | cut -c1-8
  else echo -n "$1" | cksum | cut -d' ' -f1; fi
}

emit_task_event() {
  local event_type="$1"
  local task_id="$2"
  local task_key="$3"
  local task_subject="$4"
  local task_status="$5"

  jq -cn \
    --arg type "task_event" \
    --arg timestamp "$TIMESTAMP" \
    --arg session_id "$SESSION_ID" \
    --arg event "$event_type" \
    --arg task_id "$task_id" \
    --arg task_key "$task_key" \
    --arg task_subject "$task_subject" \
    --arg task_status "$task_status" \
    --argjson cost_snapshot_usd "$COST_SNAP" \
    --argjson token_snapshot "$TOKEN_SNAP" \
    '{
      type: $type,
      timestamp: $timestamp,
      session_id: $session_id,
      event: $event,
      task_id: $task_id,
      task_key: $task_key,
      task_subject: $task_subject,
      task_status: $task_status,
      cost_snapshot_usd: $cost_snapshot_usd,
      token_snapshot: $token_snapshot
    }' >> "$LOG_FILE"
}

case "$HOOK_EVENT" in
  "PostToolUse")
    if [ "$TOOL_NAME" = "TodoWrite" ]; then
      TODOS=$(echo "$INPUT" | jq -c '.tool_input.todos // []')
      NUM_TODOS=$(echo "$TODOS" | jq 'length')
      if [ "$NUM_TODOS" -eq 0 ]; then
        echo "{}"
        exit 0
      fi
      for i in $(seq 0 $((NUM_TODOS - 1))); do
        TASK_CONTENT=$(echo "$TODOS" | jq -r ".[$i].content // \\"\\"")
        TASK_STATUS=$(echo "$TODOS" | jq -r ".[$i].status // \\"pending\\"")
        TASK_KEY="task-$(hash_string "$TASK_CONTENT")"
        LAST_EVENT=$(grep "\"task_key\":\"$TASK_KEY\"" "$LOG_FILE" 2>/dev/null | tail -1 || echo "")
        LAST_STATUS=""
        LAST_TASK_ID=""
        if [ -n "$LAST_EVENT" ]; then
          LAST_STATUS=$(echo "$LAST_EVENT" | jq -r '.task_status // ""')
          LAST_TASK_ID=$(echo "$LAST_EVENT" | jq -r '.task_id // ""')
        fi
        EVENT_TYPE=""
        TASK_ID="$LAST_TASK_ID"
        if [ "$TASK_STATUS" = "in_progress" ] && [ "$LAST_STATUS" != "in_progress" ]; then
          EVENT_TYPE="task_started"
          TASK_ID="\${TASK_KEY}-\${RUN_ID}-\${i}"
        elif [ "$TASK_STATUS" = "completed" ] && [ "$LAST_STATUS" != "completed" ]; then
          EVENT_TYPE="task_completed"
          if [ -z "$TASK_ID" ]; then TASK_ID="\${TASK_KEY}-\${RUN_ID}-\${i}"; fi
        elif [ "$TASK_STATUS" != "$LAST_STATUS" ] && [ -n "$LAST_STATUS" ]; then
          EVENT_TYPE="task_updated"
          if [ -z "$TASK_ID" ]; then TASK_ID="\${TASK_KEY}-\${RUN_ID}-\${i}"; fi
        fi
        if [ -n "$EVENT_TYPE" ]; then
          emit_task_event "$EVENT_TYPE" "$TASK_ID" "$TASK_KEY" "$TASK_CONTENT" "$TASK_STATUS"
        fi
      done
    fi ;;
esac
echo "{}"
`;

export function isInstalled(): boolean {
  const home = os.homedir();
  const settingsPath = path.join(home, '.claude', 'settings.json');
  if (!fs.existsSync(settingsPath)) { return false; }

  try {
    const settings = JSON.parse(fs.readFileSync(settingsPath, 'utf-8'));
    return settings.statusLine?.command?.includes('.claude-status') || false;
  } catch {
    return false;
  }
}

export async function installHooks(): Promise<boolean> {
  const home = os.homedir();
  const hooksDir = path.join(home, '.claude-status', 'hooks');
  const sessionsDir = path.join(home, '.claude-status', 'sessions');
  const claudeDir = path.join(home, '.claude');
  const settingsPath = path.join(claudeDir, 'settings.json');

  try {
    // Create directories
    fs.mkdirSync(hooksDir, { recursive: true });
    fs.mkdirSync(sessionsDir, { recursive: true });
    fs.mkdirSync(claudeDir, { recursive: true });

    // Write hook scripts
    const statusLinePath = path.join(hooksDir, 'status-line.sh');
    const taskHookPath = path.join(hooksDir, 'task-hook.sh');
    fs.writeFileSync(statusLinePath, STATUS_LINE_SCRIPT, { mode: 0o755 });
    fs.writeFileSync(taskHookPath, TASK_HOOK_SCRIPT, { mode: 0o755 });

    // Read or create settings
    let settings: Record<string, any> = {};
    if (fs.existsSync(settingsPath)) {
      // Backup
      const data = fs.readFileSync(settingsPath, 'utf-8');
      fs.writeFileSync(settingsPath + '.backup', data);
      settings = JSON.parse(data);
    }

    // Set statusLine
    settings.statusLine = {
      type: 'command',
      command: `bash ${statusLinePath}`,
    };

    // Set hooks
    if (!settings.hooks) { settings.hooks = {}; }

    const taskHookCmd = `bash ${taskHookPath}`;

    const addHook = (event: string, matcher?: string) => {
      if (!settings.hooks[event]) { settings.hooks[event] = []; }
      const exists = settings.hooks[event].some((h: any) =>
        h.hooks?.some((a: any) => a.command?.includes('.claude-status'))
      );
      if (!exists) {
        const entry: any = {
          hooks: [{ type: 'command', command: taskHookCmd }],
        };
        if (matcher) { entry.matcher = matcher; }
        settings.hooks[event].push(entry);
      }
    };

    addHook('PostToolUse', 'TodoWrite');
    // Write settings
    fs.writeFileSync(settingsPath, JSON.stringify(settings, null, 2));

    return true;
  } catch (err) {
    vscode.window.showErrorMessage(`Failed to install hooks: ${err}`);
    return false;
  }
}

export async function uninstallHooks(): Promise<boolean> {
  const home = os.homedir();
  const hooksDir = path.join(home, '.claude-status', 'hooks');
  const settingsPath = path.join(home, '.claude', 'settings.json');

  try {
    if (fs.existsSync(settingsPath)) {
      const data = fs.readFileSync(settingsPath, 'utf-8');
      fs.writeFileSync(settingsPath + '.backup', data);
      const settings = JSON.parse(data);

      // Remove statusLine
      if (settings.statusLine?.command?.includes('.claude-status')) {
        delete settings.statusLine;
      }

      // Remove hooks
      if (settings.hooks) {
        for (const event of Object.keys(settings.hooks)) {
          settings.hooks[event] = settings.hooks[event].filter((h: any) =>
            !h.hooks?.some((a: any) => a.command?.includes('.claude-status'))
          );
          if (settings.hooks[event].length === 0) { delete settings.hooks[event]; }
        }
        if (Object.keys(settings.hooks).length === 0) { delete settings.hooks; }
      }

      fs.writeFileSync(settingsPath, JSON.stringify(settings, null, 2));
    }

    // Remove hook scripts
    for (const name of ['status-line.sh', 'task-hook.sh']) {
      const p = path.join(hooksDir, name);
      if (fs.existsSync(p)) { fs.unlinkSync(p); }
    }

    return true;
  } catch (err) {
    vscode.window.showErrorMessage(`Failed to uninstall hooks: ${err}`);
    return false;
  }
}
