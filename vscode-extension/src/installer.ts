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

printf '{"type":"snapshot","timestamp":"%s","session_id":"%s","total_cost_usd":%s,"total_input_tokens":%s,"total_output_tokens":%s,"cache_read_tokens":%s,"cache_write_tokens":%s,"context_used_pct":%s,"context_window_size":%s,"total_duration_ms":%s,"total_api_duration_ms":%s,"total_lines_added":%s,"total_lines_removed":%s,"model":"%s"}\\n' \\
  "$TIMESTAMP" "$SESSION_ID" "$TOTAL_COST" "$TOTAL_INPUT" "$TOTAL_OUTPUT" \\
  "$CACHE_READ" "$CACHE_WRITE" "$CTX_PCT" "$CTX_SIZE" "$TOTAL_DURATION" \\
  "$API_DURATION" "$LINES_ADDED" "$LINES_REMOVED" "$MODEL" >> "$LOG_FILE"

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

case "$HOOK_EVENT" in
  "PostToolUse")
    if [ "$TOOL_NAME" = "TodoWrite" ]; then
      TODOS=$(echo "$INPUT" | jq -c '.tool_input.todos // []')
      NUM_TODOS=$(echo "$TODOS" | jq 'length')
      for i in $(seq 0 $((NUM_TODOS - 1))); do
        TASK_CONTENT=$(echo "$TODOS" | jq -r ".[$i].content // \\"\\"")
        TASK_STATUS=$(echo "$TODOS" | jq -r ".[$i].status // \\"pending\\"")
        TASK_ID="task-$(hash_string "$TASK_CONTENT")"
        EVENT_TYPE="task_updated"
        if [ "$TASK_STATUS" = "in_progress" ]; then EVENT_TYPE="task_started"
        elif [ "$TASK_STATUS" = "completed" ]; then EVENT_TYPE="task_completed"; fi
        ESCAPED_CONTENT=$(echo "$TASK_CONTENT" | sed 's/"/\\\\"/g')
        printf '{"type":"task_event","timestamp":"%s","session_id":"%s","event":"%s","task_id":"%s","task_subject":"%s","task_status":"%s","cost_snapshot_usd":%s,"token_snapshot":%s}\\n' \\
          "$TIMESTAMP" "$SESSION_ID" "$EVENT_TYPE" "$TASK_ID" "$ESCAPED_CONTENT" "$TASK_STATUS" "$COST_SNAP" "$TOKEN_SNAP" >> "$LOG_FILE"
      done
    fi ;;
  "TaskCompleted")
    TASK_ID=$(echo "$INPUT" | jq -r '.task_id // "unknown"')
    TASK_SUBJECT=$(echo "$INPUT" | jq -r '.task_subject // "unknown"' | sed 's/"/\\\\"/g')
    printf '{"type":"task_event","timestamp":"%s","session_id":"%s","event":"task_completed","task_id":"%s","task_subject":"%s","task_status":"completed","cost_snapshot_usd":%s,"token_snapshot":%s}\\n' \\
      "$TIMESTAMP" "$SESSION_ID" "$TASK_ID" "$TASK_SUBJECT" "$COST_SNAP" "$TOKEN_SNAP" >> "$LOG_FILE"
    ;;
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
    addHook('TaskCompleted');
    addHook('SessionEnd');

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
