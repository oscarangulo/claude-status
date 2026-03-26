import * as vscode from 'vscode';
import * as fs from 'fs';
import {
  getSessionsDir,
  getActiveSessionFile,
  parseSessionFile,
  computeMetrics,
  formatTokens,
  SessionData,
} from './session';

let statusBarItem: vscode.StatusBarItem;
let detailBarItem: vscode.StatusBarItem;
let watcher: fs.FSWatcher | null = null;
let refreshInterval: NodeJS.Timeout | null = null;

export function activate(context: vscode.ExtensionContext) {
  statusBarItem = vscode.window.createStatusBarItem(vscode.StatusBarAlignment.Left, 100);
  statusBarItem.command = 'claude-status.showDetails';
  statusBarItem.name = 'Claude Status';
  context.subscriptions.push(statusBarItem);

  detailBarItem = vscode.window.createStatusBarItem(vscode.StatusBarAlignment.Left, 99);
  detailBarItem.name = 'Claude Status Detail';
  context.subscriptions.push(detailBarItem);

  context.subscriptions.push(
    vscode.commands.registerCommand('claude-status.showDetails', showDetailsPanel),
    vscode.commands.registerCommand('claude-status.refresh', () => updateStatusBar()),
  );

  updateStatusBar();
  startWatching();

  refreshInterval = setInterval(updateStatusBar, 5000);
  context.subscriptions.push({ dispose: () => {
    if (refreshInterval) { clearInterval(refreshInterval); }
    if (watcher) { watcher.close(); }
  }});
}

function startWatching() {
  const dir = getSessionsDir();
  if (!fs.existsSync(dir)) {
    setTimeout(startWatching, 10000);
    return;
  }
  try {
    watcher = fs.watch(dir, (_eventType, filename) => {
      if (filename && filename.endsWith('.jsonl')) {
        updateStatusBar();
      }
    });
  } catch {
    // Fallback to polling
  }
}

function updateStatusBar() {
  const file = getActiveSessionFile();
  if (!file) {
    statusBarItem.text = '$(pulse) Claude: no sessions yet';
    statusBarItem.tooltip = new vscode.MarkdownString(
      '**No session data found**\n\n' +
      'Make sure hooks are installed:\n\n' +
      '```\nclaude-status install\n```\n\n' +
      'Then start a new Claude Code session.\n\n' +
      '_Data appears in `~/.claude-status/sessions/`_'
    );
    statusBarItem.show();
    detailBarItem.hide();
    return;
  }

  let session: SessionData;
  try {
    session = parseSessionFile(file);
  } catch {
    return;
  }

  const m = computeMetrics(session);
  if (!m) {
    statusBarItem.text = '$(pulse) Claude: waiting for next response...';
    statusBarItem.tooltip = new vscode.MarkdownString(
      '**Session found but no cost data yet**\n\n' +
      'Data will appear after Claude\'s next response.\n\n' +
      'If nothing appears after a few messages, verify hooks are installed:\n\n' +
      '```\nclaude-status install\n```'
    );
    statusBarItem.show();
    detailBarItem.hide();
    return;
  }

  // Cost icon
  let costIcon = '$(check)';
  if (m.cost > 1) { costIcon = '$(flame)'; }
  else if (m.cost > 0.5) { costIcon = '$(warning)'; }

  // --- Status bar line 1: Spent, speed, time, code ---
  let mainText = `${costIcon} Spent $${m.cost.toFixed(4)}`;
  if (m.burnRate > 0) {
    mainText += ` ($${m.burnRate.toFixed(3)}/min)`;
  }
  mainText += ` | ${m.duration}`;
  if (m.linesAdded > 0 || m.linesRemoved > 0) {
    mainText += ` | ${m.linesAdded} added, ${m.linesRemoved} removed`;
  }

  statusBarItem.text = mainText;
  statusBarItem.tooltip = buildTooltip(m);
  statusBarItem.show();

  // --- Status bar line 2: Memory, savings, task ---
  let memoryPct = m.contextPct;
  let detailText = `Memory ${memoryPct}%`;
  if (memoryPct >= 80) { detailText += ' $(alert) almost full!'; }

  if (m.cacheSavings > 0.001) {
    detailText += ` | Saved $${m.cacheSavings.toFixed(4)} from cache`;
  }

  if (m.currentTask) {
    const subject = m.currentTask.subject.length > 25
      ? m.currentTask.subject.slice(0, 22) + '...'
      : m.currentTask.subject;
    detailText += ` | $(play) ${subject} ($${m.currentTask.costDelta.toFixed(4)})`;
  }

  detailBarItem.text = detailText;
  detailBarItem.show();
}

function buildTooltip(m: ReturnType<typeof computeMetrics>): vscode.MarkdownString {
  if (!m) { return new vscode.MarkdownString('No data'); }

  const md = new vscode.MarkdownString();
  md.isTrusted = true;
  md.supportThemeIcons = true;

  md.appendMarkdown(`**${m.model}** — Session cost: **$${m.cost.toFixed(4)}**\n\n`);

  if (m.burnRate > 0) {
    md.appendMarkdown(`Spending $${m.burnRate.toFixed(3)} per minute\n\n`);
  }

  md.appendMarkdown(`Reading ${formatTokens(m.inputTokens)} tokens, writing ${formatTokens(m.outputTokens)} tokens\n\n`);

  if (m.cacheSavings > 0.001) {
    md.appendMarkdown(`Cache saved you **$${m.cacheSavings.toFixed(4)}** (${m.cacheHitRate.toFixed(0)}% reused)\n\n`);
  }

  if (m.currentTask) {
    md.appendMarkdown(`Working on: **${m.currentTask.subject}** ($${m.currentTask.costDelta.toFixed(4)} so far)\n\n`);
  }

  md.appendMarkdown(`_Click for full breakdown_`);

  return md;
}

function showDetailsPanel() {
  const file = getActiveSessionFile();
  if (!file) {
    vscode.window.showInformationMessage('No active Claude Code session. Run `claude-status install` first.');
    return;
  }

  const session = parseSessionFile(file);
  const m = computeMetrics(session);
  if (!m) {
    vscode.window.showInformationMessage('Session has no data yet.');
    return;
  }

  const items: vscode.QuickPickItem[] = [
    {
      label: `$(credit-card) Total spent: $${m.cost.toFixed(4)}`,
      description: m.burnRate > 0 ? `Spending $${m.burnRate.toFixed(3)}/min` : '',
    },
    {
      label: `$(book) Tokens used: ${formatTokens(m.totalTokens)}`,
      description: `${formatTokens(m.inputTokens)} reading, ${formatTokens(m.outputTokens)} writing`,
    },
    {
      label: `$(savings) Cache savings: $${m.cacheSavings.toFixed(4)}`,
      description: `${m.cacheHitRate.toFixed(0)}% of input was reused from cache`,
    },
    {
      label: `$(browser) Memory used: ${m.contextPct}%`,
      description: m.contextPct >= 80 ? 'Almost full! Use /compact to free space' : `${100 - m.contextPct}% remaining`,
    },
    {
      label: `$(clock) Session time: ${m.duration}`,
      description: `Using ${m.model}`,
    },
  ];

  if (m.linesAdded > 0 || m.linesRemoved > 0) {
    items.push({
      label: `$(code) Code changes: ${m.linesAdded} lines added, ${m.linesRemoved} removed`,
      description: '',
    });
  }

  if (m.currentTask) {
    items.push({
      label: `$(play) Working on: ${m.currentTask.subject}`,
      description: `$${m.currentTask.costDelta.toFixed(4)} spent on this task`,
    });
  }

  // Completed tasks
  const completedTasks = new Map<string, { subject: string; startCost: number; endCost: number }>();
  for (const t of session.tasks) {
    if (t.event === 'task_started') {
      completedTasks.set(t.task_subject, { subject: t.task_subject, startCost: t.cost_snapshot_usd, endCost: 0 });
    }
    if (t.event === 'task_completed') {
      const existing = completedTasks.get(t.task_subject);
      if (existing) { existing.endCost = t.cost_snapshot_usd; }
    }
  }

  let hasCompleted = false;
  for (const [, task] of completedTasks) {
    if (task.endCost > 0) {
      const delta = task.endCost - task.startCost;
      if (!hasCompleted) {
        items.push({ label: '', description: '', kind: vscode.QuickPickItemKind.Separator });
        hasCompleted = true;
      }
      items.push({
        label: `$(check) ${task.subject}`,
        description: `Cost $${delta.toFixed(4)}`,
      });
    }
  }

  vscode.window.showQuickPick(items, {
    title: `Claude Session — ${m.model}`,
    placeHolder: 'Your session at a glance (click any item to close)',
  });
}

export function deactivate() {
  if (watcher) { watcher.close(); }
  if (refreshInterval) { clearInterval(refreshInterval); }
}
