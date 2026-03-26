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
}

// Model pricing per token
const PRICING: Record<string, { input: number; output: number; cacheRead: number }> = {
  opus:   { input: 5 / 1e6,  output: 25 / 1e6, cacheRead: 0.5 / 1e6 },
  sonnet: { input: 3 / 1e6,  output: 15 / 1e6, cacheRead: 0.3 / 1e6 },
  haiku:  { input: 1 / 1e6,  output: 5 / 1e6,  cacheRead: 0.1 / 1e6 },
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

export function getActiveSessionFile(): string | null {
  const dir = getSessionsDir();
  if (!fs.existsSync(dir)) { return null; }

  const files = fs.readdirSync(dir)
    .filter(f => f.endsWith('.jsonl'))
    .map(f => ({
      name: f,
      mtime: fs.statSync(path.join(dir, f)).mtimeMs,
    }))
    .sort((a, b) => b.mtime - a.mtime);

  if (files.length === 0) { return null; }
  return path.join(dir, files[0].name);
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

  // Find current running task
  let currentTask: SessionData['currentTask'] = null;
  const startedTasks = tasks.filter(t => t.event === 'task_started');
  if (startedTasks.length > 0 && latest) {
    const lastStarted = startedTasks[startedTasks.length - 1];
    const isCompleted = tasks.some(
      t => t.task_id === lastStarted.task_id && t.event === 'task_completed'
    );
    if (!isCompleted) {
      currentTask = {
        subject: lastStarted.task_subject,
        costDelta: latest.total_cost_usd - lastStarted.cost_snapshot_usd,
      };
    }
  }

  return { id, latest, tasks, currentTask };
}

export function computeMetrics(session: SessionData) {
  const s = session.latest;
  if (!s) { return null; }

  const totalTokens = s.total_input_tokens + s.total_output_tokens;
  const totalIn = (s.total_input_tokens - s.cache_read_tokens) + s.cache_read_tokens;
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
  };
}

export function formatTokens(n: number): string {
  if (n >= 1_000_000) { return `${(n / 1_000_000).toFixed(1)}M`; }
  if (n >= 1_000) { return `${(n / 1_000).toFixed(1)}K`; }
  return `${n}`;
}
