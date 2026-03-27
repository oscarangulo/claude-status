import * as fs from 'fs';
import * as path from 'path';
import * as os from 'os';

export interface Snapshot {
  type: 'snapshot';
  timestamp: string;
  session_id: string;
  total_cost_usd: number;
  total_input_tokens: number;
  total_output_tokens: number;
  cache_read_tokens: number;
  cache_write_tokens: number;
  context_used_pct: number;
  context_window_size: number;
  total_duration_ms: number;
  total_api_duration_ms: number;
  total_lines_added: number;
  total_lines_removed: number;
  model: string;
}

export interface TaskEvent {
  type: 'task_event';
  timestamp: string;
  session_id: string;
  event: 'task_started' | 'task_completed' | 'task_updated';
  task_id: string;
  task_subject: string;
  task_status: string;
  cost_snapshot_usd: number;
  token_snapshot: number;
}

export interface SessionData {
  id: string;
  latest: Snapshot | null;
  tasks: TaskEvent[];
  currentTask: { subject: string; costDelta: number } | null;
  source: 'snapshot' | 'native';
}

// Model pricing per token
const PRICING: Record<string, { input: number; output: number; cacheRead: number; cacheWrite: number }> = {
  opus:   { input: 5 / 1e6,  output: 25 / 1e6, cacheRead: 0.5 / 1e6, cacheWrite: 6.25 / 1e6 },
  sonnet: { input: 3 / 1e6,  output: 15 / 1e6, cacheRead: 0.3 / 1e6, cacheWrite: 3.75 / 1e6 },
  haiku:  { input: 1 / 1e6,  output: 5 / 1e6,  cacheRead: 0.1 / 1e6, cacheWrite: 1.25 / 1e6 },
};

function getModelPricing(model: string) {
  const m = model.toLowerCase();
  if (m.includes('haiku')) { return PRICING.haiku; }
  if (m.includes('sonnet')) { return PRICING.sonnet; }
  return PRICING.opus;
}

export function getSessionsDir(): string {
  return path.join(os.homedir(), '.claude-status', 'sessions');
}

function getClaudeProjectsDir(): string {
  return path.join(os.homedir(), '.claude', 'projects');
}

function listProjectSessionFiles(): string[] {
  const projectsDir = getClaudeProjectsDir();
  if (!fs.existsSync(projectsDir)) { return []; }

  const files: string[] = [];
  for (const entry of fs.readdirSync(projectsDir, { withFileTypes: true })) {
    if (!entry.isDirectory()) { continue; }
    const dirPath = path.join(projectsDir, entry.name);
    for (const child of fs.readdirSync(dirPath, { withFileTypes: true })) {
      if (!child.isFile()) { continue; }
      if (!child.name.endsWith('.jsonl')) { continue; }
      if (child.name === 'sessions-index.json') { continue; }
      files.push(path.join(dirPath, child.name));
    }
  }

  return files;
}

export function getActiveSessionFile(): string | null {
  const files = [
    ...(
      fs.existsSync(getSessionsDir())
        ? fs.readdirSync(getSessionsDir())
            .filter(f => f.endsWith('.jsonl'))
            .map(f => path.join(getSessionsDir(), f))
        : []
    ),
    ...listProjectSessionFiles(),
  ]
    .filter(file => {
      try {
        return fs.statSync(file).size > 0;
      } catch {
        return false;
      }
    })
    .map(file => ({
      name: file,
      mtime: fs.statSync(file).mtimeMs,
    }))
    .sort((a, b) => b.mtime - a.mtime);

  if (files.length === 0) { return null; }
  return files[0].name;
}

interface NativeUsage {
  input_tokens?: number;
  output_tokens?: number;
  cache_read_input_tokens?: number;
  cache_creation_input_tokens?: number;
}

interface NativeEntry {
  type?: string;
  timestamp?: string;
  sessionId?: string;
  message?: {
    model?: string;
    usage?: NativeUsage;
  };
}

function parseNativeSession(lines: string[], filePath: string): SessionData {
  let id = path.basename(filePath, '.jsonl');
  let latestSnapshot: Snapshot | null = null;
  let firstTimestamp = 0;
  let latestTimestamp = 0;

  let totalCost = 0;
  let totalInputTokens = 0;
  let totalOutputTokens = 0;
  let cacheReadTokens = 0;
  let cacheWriteTokens = 0;
  let model = 'unknown';

  for (const line of lines) {
    try {
      const entry = JSON.parse(line) as NativeEntry;
      if (entry.sessionId) { id = entry.sessionId; }
      if (entry.type !== 'assistant' || !entry.message?.usage || !entry.timestamp) {
        continue;
      }

      const ts = new Date(entry.timestamp).getTime();
      if (!Number.isFinite(ts)) { continue; }
      if (firstTimestamp === 0 || ts < firstTimestamp) { firstTimestamp = ts; }
      if (ts > latestTimestamp) { latestTimestamp = ts; }

      const pricing = getModelPricing(entry.message.model || '');
      const usage = entry.message.usage;
      const input = usage.input_tokens || 0;
      const output = usage.output_tokens || 0;
      const cacheRead = usage.cache_read_input_tokens || 0;
      const cacheWrite = usage.cache_creation_input_tokens || 0;

      totalInputTokens += input;
      totalOutputTokens += output;
      cacheReadTokens += cacheRead;
      cacheWriteTokens += cacheWrite;
      totalCost +=
        input * pricing.input +
        output * pricing.output +
        cacheRead * pricing.cacheRead +
        cacheWrite * pricing.cacheWrite;
      model = entry.message.model || model;
    } catch {
      // skip malformed lines
    }
  }

  if (latestTimestamp > 0) {
    latestSnapshot = {
      type: 'snapshot',
      timestamp: new Date(latestTimestamp).toISOString(),
      session_id: id,
      total_cost_usd: totalCost,
      total_input_tokens: totalInputTokens,
      total_output_tokens: totalOutputTokens,
      cache_read_tokens: cacheReadTokens,
      cache_write_tokens: cacheWriteTokens,
      context_used_pct: 0,
      context_window_size: 0,
      total_duration_ms: Math.max(0, latestTimestamp - firstTimestamp),
      total_api_duration_ms: 0,
      total_lines_added: 0,
      total_lines_removed: 0,
      model,
    };
  }

  return {
    id,
    latest: latestSnapshot,
    tasks: [],
    currentTask: null,
    source: 'native',
  };
}

export function parseSessionFile(filePath: string): SessionData {
  const content = fs.readFileSync(filePath, 'utf-8');
  const lines = content.split('\n').filter(l => l.trim());

  let latest: Snapshot | null = null;
  const tasks: TaskEvent[] = [];
  let id = '';

  for (const line of lines) {
    try {
      const entry = JSON.parse(line);
      if (!id && entry.session_id) { id = entry.session_id; }

      if (entry.type === 'snapshot') {
        latest = entry as Snapshot;
      } else if (entry.type === 'task_event') {
        tasks.push(entry as TaskEvent);
      }
    } catch {
      // skip malformed lines
    }
  }

  if (!latest) {
    return parseNativeSession(lines, filePath);
  }

  // Find current running task
  let currentTask: SessionData['currentTask'] = null;
  if (latest) {
    const latestByTask = new Map<string, TaskEvent>();
    for (const task of tasks) {
      latestByTask.set(task.task_id || task.task_subject, task);
    }

    let runningTask: TaskEvent | null = null;
    for (const task of latestByTask.values()) {
      if (task.task_status === 'in_progress' || task.event === 'task_started') {
        if (!runningTask || new Date(task.timestamp).getTime() > new Date(runningTask.timestamp).getTime()) {
          runningTask = task;
        }
      }
    }

    if (runningTask) {
      currentTask = {
        subject: runningTask.task_subject,
        costDelta: Math.max(0, latest.total_cost_usd - runningTask.cost_snapshot_usd),
      };
    }
  }

  return { id, latest, tasks, currentTask, source: 'snapshot' };
}

export function computeMetrics(session: SessionData) {
  const s = session.latest;
  if (!s) { return null; }

  const totalTokens = s.total_input_tokens + s.total_output_tokens;
  const totalIn = s.total_input_tokens + s.cache_read_tokens;
  const cacheHitRate = totalIn > 0 ? (s.cache_read_tokens / totalIn) * 100 : 0;

  const pricing = getModelPricing(s.model);
  const cacheSavings = s.cache_read_tokens * (pricing.input - pricing.cacheRead);

  let burnRate = 0;
  if (s.total_duration_ms > 60000) {
    burnRate = s.total_cost_usd / (s.total_duration_ms / 60000);
  }

  const durationSec = Math.floor(s.total_duration_ms / 1000);
  let duration: string;
  if (durationSec >= 3600) {
    duration = `${Math.floor(durationSec / 3600)}h${Math.floor((durationSec % 3600) / 60)}m`;
  } else if (durationSec >= 60) {
    duration = `${Math.floor(durationSec / 60)}m${durationSec % 60}s`;
  } else {
    duration = `${durationSec}s`;
  }

  return {
    cost: s.total_cost_usd,
    totalTokens,
    inputTokens: s.total_input_tokens,
    outputTokens: s.total_output_tokens,
    cacheReadTokens: s.cache_read_tokens,
    cacheWriteTokens: s.cache_write_tokens,
    cacheHitRate,
    cacheSavings,
    contextPct: s.context_used_pct,
    burnRate,
    duration,
    linesAdded: s.total_lines_added,
    linesRemoved: s.total_lines_removed,
    model: s.model,
    currentTask: session.currentTask,
    source: session.source,
  };
}

export function formatTokens(n: number): string {
  if (n >= 1_000_000) { return `${(n / 1_000_000).toFixed(1)}M`; }
  if (n >= 1_000) { return `${(n / 1_000).toFixed(1)}K`; }
  return `${n}`;
}
