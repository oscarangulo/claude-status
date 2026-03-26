import * as vscode from 'vscode';
import * as fs from 'fs';
import * as path from 'path';
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
  // Main status bar item (left side, high priority)
  statusBarItem = vscode.window.createStatusBarItem(vscode.StatusBarAlignment.Left, 100);
  statusBarItem.command = 'claude-status.showDetails';
  statusBarItem.name = 'Claude Status';
  context.subscriptions.push(statusBarItem);

  // Second line for context/cache
  detailBarItem = vscode.window.createStatusBarItem(vscode.StatusBarAlignment.Left, 99);
  detailBarItem.name = 'Claude Status Detail';
  context.subscriptions.push(detailBarItem);

  // Commands
  context.subscriptions.push(
    vscode.commands.registerCommand('claude-status.showDetails', showDetailsPanel),
    vscode.commands.registerCommand('claude-status.refresh', () => updateStatusBar()),
  );

  // Initial update
  updateStatusBar();

  // Watch session directory for changes
  startWatching();

  // Fallback polling every 5s (in case watcher misses events)
  refreshInterval = setInterval(updateStatusBar, 5000);
  context.subscriptions.push({ dispose: () => {
    if (refreshInterval) { clearInterval(refreshInterval); }
    if (watcher) { watcher.close(); }
  }});
}

function startWatching() {
  const dir = getSessionsDir();
  if (!fs.existsSync(dir)) {
    // Retry in 10s if directory doesn't exist yet
    setTimeout(startWatching, 10000);
    return;
  }

  try {
    watcher = fs.watch(dir, (eventType, filename) => {
      if (filename && filename.endsWith('.jsonl')) {
        updateStatusBar();
      }
    });
  } catch {
    // Fallback to polling only
  }
}

function updateStatusBar() {
  const file = getActiveSessionFile();
  if (!file) {
    statusBarItem.text = '$(pulse) Claude: no session';
    statusBarItem.tooltip = 'No active Claude Code session detected.\nRun `claude-status install` to configure hooks.';
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
    statusBarItem.text = '$(pulse) Claude: waiting...';
    statusBarItem.show();
    detailBarItem.hide();
    return;
  }

  // Cost icon based on amount
  let costIcon = '$(check)';
  if (m.cost > 1) { costIcon = '$(flame)'; }
  else if (m.cost > 0.5) { costIcon = '$(warning)'; }

  // Main bar: cost | tokens | burn rate | duration
  let mainText = `${costIcon} $${m.cost.toFixed(4)}`;
  mainText += ` | ${formatTokens(m.totalTokens)} tok`;
  if (m.burnRate > 0) {
    mainText += ` | ${m.burnRate.toFixed(3)}/min`;
  }
  mainText += ` | ${m.duration}`;
  if (m.linesAdded > 0 || m.linesRemoved > 0) {
    mainText += ` | +${m.linesAdded}/-${m.linesRemoved}`;
  }

  statusBarItem.text = mainText;
  statusBarItem.tooltip = buildTooltip(m);
  statusBarItem.show();

  // Detail bar: context | cache | task
  let detailText = `ctx:${m.contextPct}%`;
  if (m.contextPct >= 80) { detailText += ' $(alert)'; }
  detailText += ` | cache:${m.cacheHitRate.toFixed(0)}%`;
  if (m.cacheSavings > 0.001) {
    detailText += ` saved $${m.cacheSavings.toFixed(4)}`;
  }
  if (m.currentTask) {
    const subject = m.currentTask.subject.length > 25
      ? m.currentTask.subject.slice(0, 22) + '...'
      : m.currentTask.subject;
    detailText += ` | $(play) ${subject} $${m.currentTask.costDelta.toFixed(4)}`;
  }

  detailBarItem.text = detailText;
  detailBarItem.show();
}

function buildTooltip(m: ReturnType<typeof computeMetrics>): vscode.MarkdownString {
  if (!m) { return new vscode.MarkdownString('No data'); }

  const md = new vscode.MarkdownString();
  md.isTrusted = true;
  md.supportThemeIcons = true;

  md.appendMarkdown(`### $(pulse) Claude Status\n\n`);
  md.appendMarkdown(`**Model:** ${m.model}\n\n`);
  md.appendMarkdown(`---\n\n`);

  md.appendMarkdown(`#### Cost\n`);
  md.appendMarkdown(`| | |\n|---|---|\n`);
  md.appendMarkdown(`| Total | **$${m.cost.toFixed(4)}** |\n`);
  if (m.burnRate > 0) {
    md.appendMarkdown(`| Burn rate | $${m.burnRate.toFixed(4)}/min |\n`);
  }
  md.appendMarkdown(`| Duration | ${m.duration} |\n\n`);

  md.appendMarkdown(`#### Tokens\n`);
  md.appendMarkdown(`| | |\n|---|---|\n`);
  md.appendMarkdown(`| Input | ${formatTokens(m.inputTokens)} |\n`);
  md.appendMarkdown(`| Output | ${formatTokens(m.outputTokens)} _(5x cost)_ |\n`);
  md.appendMarkdown(`| Cache read | ${formatTokens(m.cacheReadTokens)} _(10x cheaper)_ |\n`);
  md.appendMarkdown(`| Cache write | ${formatTokens(m.cacheWriteTokens)} |\n`);
  md.appendMarkdown(`| Cache hit rate | **${m.cacheHitRate.toFixed(0)}%** |\n`);
  if (m.cacheSavings > 0.001) {
    md.appendMarkdown(`| Cache savings | **$${m.cacheSavings.toFixed(4)}** |\n`);
  }
  md.appendMarkdown(`\n`);

  md.appendMarkdown(`#### Context\n`);
  const bar = '█'.repeat(Math.floor(m.contextPct / 10)) + '░'.repeat(10 - Math.floor(m.contextPct / 10));
  md.appendMarkdown(`${bar} **${m.contextPct}%**`);
  if (m.contextPct >= 80) {
    md.appendMarkdown(` $(warning) Use \`/compact\``);
  }
  md.appendMarkdown(`\n\n`);

  if (m.linesAdded > 0 || m.linesRemoved > 0) {
    md.appendMarkdown(`#### Code\n`);
    md.appendMarkdown(`+${m.linesAdded} / -${m.linesRemoved} lines\n\n`);
  }

  if (m.currentTask) {
    md.appendMarkdown(`---\n\n`);
    md.appendMarkdown(`#### $(play) Current Task\n`);
    md.appendMarkdown(`**${m.currentTask.subject}**\n\n`);
    md.appendMarkdown(`Cost so far: **$${m.currentTask.costDelta.toFixed(4)}**\n`);
  }

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

  // Show quick pick with session info
  const items: vscode.QuickPickItem[] = [
    { label: `$(credit-card) Cost: $${m.cost.toFixed(4)}`, description: m.burnRate > 0 ? `${m.burnRate.toFixed(4)}/min` : '' },
    { label: `$(symbol-number) Tokens: ${formatTokens(m.totalTokens)}`, description: `in:${formatTokens(m.inputTokens)} out:${formatTokens(m.outputTokens)}` },
    { label: `$(database) Cache: ${m.cacheHitRate.toFixed(0)}% hit rate`, description: m.cacheSavings > 0.001 ? `saved $${m.cacheSavings.toFixed(4)}` : '' },
    { label: `$(browser) Context: ${m.contextPct}%`, description: m.contextPct >= 80 ? 'Use /compact!' : '' },
    { label: `$(clock) Duration: ${m.duration}`, description: '' },
  ];

  if (m.linesAdded > 0 || m.linesRemoved > 0) {
    items.push({ label: `$(code) Code: +${m.linesAdded} / -${m.linesRemoved}`, description: '' });
  }

  if (m.currentTask) {
    items.push({ label: `$(play) Task: ${m.currentTask.subject}`, description: `$${m.currentTask.costDelta.toFixed(4)}` });
  }

  // Show completed tasks
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
  for (const [, task] of completedTasks) {
    if (task.endCost > 0) {
      const delta = task.endCost - task.startCost;
      items.push({ label: `$(check) ${task.subject}`, description: `$${delta.toFixed(4)}` });
    }
  }

  vscode.window.showQuickPick(items, {
    title: `Claude Status — ${m.model}`,
    placeHolder: 'Session details',
  });
}

export function deactivate() {
  if (watcher) { watcher.close(); }
  if (refreshInterval) { clearInterval(refreshInterval); }
}
