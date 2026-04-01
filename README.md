<p align="center">
  <img src="logo.png" alt="Claude Status" width="200">
  <h1 align="center">claude-status</h1>
  <p align="center">
    <strong>Know what Claude Code is doing. In real time. Inside your conversation.</strong>
  </p>
  <p align="center">
    <a href="https://github.com/oscarangulo/claude-status/releases"><img src="https://img.shields.io/github/v/release/oscarangulo/claude-status" alt="Release"></a>
    <a href="https://github.com/oscarangulo/claude-status/actions"><img src="https://github.com/oscarangulo/claude-status/actions/workflows/ci.yml/badge.svg" alt="CI"></a>
    <a href="LICENSE"><img src="https://img.shields.io/github/license/oscarangulo/claude-status" alt="License"></a>
  </p>
</p>

---

Claude Code is powerful but opaque. You don't know how fast your context is filling up, how many tool calls failed, or whether you should `/compact` before it's too late.

**claude-status gives you visibility.** Every few interactions, you see a pulse like this:

```
[claude-status] 3 tasks, 245K tokens, 32% ctx, 68% cache, +120/-15 lines,
                42 calls (2% errors) | top: Bash:15 Read:12 Edit:8,
                1x compacted, 45min (0.7% ctx/min)
```

At a glance you know: what got done, how much context you have left, whether cache is working, what tools Claude is using, and how fast you're burning through context.

When something goes wrong, you get a targeted alert:

```
[claude-status] Loop detected: 4 failed Bash calls in a row.
               Consider explaining the issue instead of retrying.
```

```
[claude-status] CONTEXT CRITICAL (92%): Use /compact NOW or risk losing conversation history.
```

**No dashboard. No tab to switch to. It appears right in your conversation.**

---

## Install

```bash
brew install claude-status
```

Restart Claude Code. That's it. Works immediately with zero configuration.

> **Windows/Linux without Homebrew?** See [other install options](#installation).

---

## What you see

### Session pulse

A compact summary appears every 3 interactions (configurable). Here's what each part means:

```
3 tasks, 245K tokens, 32% ctx, 68% cache, +120/-15 lines, 42 calls (2% errors) | top: Bash:15 Read:12 Edit:8, 1x compacted, 45min (0.7% ctx/min)
```

| Metric | What it means | Why it matters |
|---|---|---|
| **3 tasks** | Completed plan tasks | Track progress |
| **245K tokens** | Total tokens consumed | Session size at a glance |
| **32% ctx** | Context window used | Know when to `/compact` |
| **68% cache** | Cache hit rate | Higher = faster responses |
| **+120/-15 lines** | Code added/removed | Productivity signal |
| **42 calls (2% errors)** | Tool calls and failure rate | Spot stuck loops early |
| **top: Bash:15 Read:12 Edit:8** | Most used tools | Understand Claude's approach |
| **1x compacted** | Times `/compact` ran | Memory management awareness |
| **45min** | Session duration | Time tracking |
| **0.7% ctx/min** | Context fill speed | Predict when you'll need to compact |

Change the pulse frequency:

```bash
claude-status budget --pulse 5   # every 5 interactions instead of 3
```

---

## Smart alerts

Alerts only appear when something needs your attention. The rest of the time, claude-status is silent.

### Context watchdog

Adapts to your model automatically. Opus uses 1M tokens, Sonnet/Haiku use 200k.

> `Context window at 80%. Consider using /compact soon.`
>
> `CONTEXT CRITICAL (92%): Use /compact NOW or risk losing conversation history.`

### Loop detection

Three consecutive failures of the same tool = something's wrong. One stuck loop wastes significant time and tokens.

> `Loop detected: 4 failed Bash calls in a row. Consider explaining the issue instead of retrying.`

### Model suggestion

Opus doing lightweight work (reads, searches, globs)? You could be going faster with Sonnet.

> `Light tasks detected (reads/searches). Consider using Sonnet for this work to save ~70% on costs.`

### Idle context warning

High context usage + no activity = wasted tokens on the next message.

> `Context at 75% with 15min idle. Consider starting a new session to save tokens.`

### Subagent tracking

When Claude spawns subagents (Explore, Plan, general-purpose), each one's cost and token usage is tracked individually.

> `Expensive subagent: Explore cost $3.45. Consider using Sonnet for this type of work.`

---

## API mode (pay-per-token)

If you use the Claude API directly instead of a subscription, switch to API mode for cost-focused alerts:

```bash
claude-status budget --plan api
claude-status budget 20             # $20/day limit
claude-status budget --session 5    # $5/session limit
```

API mode adds:

| Alert | What it does |
|---|---|
| **Budget alerts** | Warns at 50%, 80%, 100% of daily/session limit |
| **Burn rate** | Alerts when spending > $0.50/min |
| **Session comparison** | Alerts when a session costs 2x your average |
| **Plan estimation** | Estimates cost before executing a multi-task plan |
| **Cost pulse** | Shows `$4.50 spent, 32% context, $0.45/min` instead of productivity metrics |

Switch back anytime:

```bash
claude-status budget --plan pro   # back to productivity mode (default)
```

---

## Spending reports

### Daily

```bash
claude-status report
```

```
  Daily Report — 2026-04-01

  Total spent:    $23.03
  Budget:         $20.00 (115% used)
  Sessions:       3
  Tasks:          8

  Avg cost/task:  $2.88
  Avg cost/sess:  $7.68
  Cache hit:      50%
```

### Weekly

```bash
claude-status report --week
```

```
  Day                Cost Sessions    Tasks
  ──────────────────────────────────────────
  Mon 03/31         $8.20        2        5
  Tue 04/01        $31.91        3       17
  Wed 04/02        $18.20        2        9
  Thu 04/03        $12.50        4       11
  Fri 04/04         $5.30        1        3
  ──────────────────────────────────────────
  Total:           $76.11   Avg/day: $15.22
```

### TUI dashboard

Run `claude-status` with no arguments for a live terminal dashboard with budget progress, context bar, token breakdown, per-task costs, subagent breakdown, and optimization tips.

---

## Works everywhere

Hooks are part of Claude Code's core engine, not the IDE. Everything works identically in:

- **Claude Code CLI** (terminal)
- **VS Code** (Claude Code extension)
- **Cursor**
- **JetBrains** (IntelliJ, WebStorm, etc.)
- **Windows** (Git Bash or WSL)

If Claude Code runs there, claude-status works there.

---

## How it works

```
You use Claude Code normally
         |
         v
After each response: pulse-hook.sh counts interactions (< 50ms)
After each tool call: snapshot-hook.sh computes metrics + checks alerts (< 50ms)
         |
         v
Every N responses  -->  Pulse with session metrics (works in conversation too)
Alert triggered?   -->  Warning appears in conversation
Nothing wrong?     -->  Silent, zero interruption
```

**Zero background processes. Zero network calls. All data stays in `~/.claude-status/`.**

Six hooks handle everything:

| Hook | Event | Role |
|------|-------|------|
| **snapshot-hook.sh** | PostToolUse | Reads session data, computes cost, tracks tool usage, runs alert checks |
| **pulse-hook.sh** | Stop | Shows periodic session pulse after every N responses |
| **task-hook.sh** | PostToolUse | Tracks per-task cost and estimates plan cost |
| **subagent-hook.sh** | SubagentStop | Calculates per-subagent cost from transcript |
| **compact-hook.sh** | PostCompact | Tracks compaction events |
| **status-line.sh** | Notification | Rich terminal status bar with live metrics |

---

## Commands

| Command | What it does |
|---------|-------------|
| `claude-status` | Live TUI dashboard |
| `claude-status budget` | Show current settings |
| `claude-status budget --plan api` | Switch to API cost mode |
| `claude-status budget --plan pro` | Switch to productivity mode (default) |
| `claude-status budget 20` | Set $20/day limit (API mode) |
| `claude-status budget --session 5` | Set $5/session limit (API mode) |
| `claude-status budget --pulse 5` | Pulse every 5 interactions |
| `claude-status budget 0` | Disable budget |
| `claude-status report` | Today's spending report |
| `claude-status report --week` | This week's spending report |
| `claude-status history` | All past sessions |
| `claude-status install` | Set up hooks |
| `claude-status update` | Upgrade and refresh hooks |
| `claude-status uninstall` | Clean removal |

---

## Installation

### Homebrew (recommended)

```bash
brew install claude-status
```

Hooks configure automatically. Just restart Claude Code.

### Go install

```bash
go install github.com/oscarangulo/claude-status/cmd/claude-status@latest
claude-status install
```

### Download binary

Grab the latest from [Releases](https://github.com/oscarangulo/claude-status/releases):

| OS | Architecture | Binary |
|----|-------------|--------|
| macOS | Apple Silicon (M1+) | `claude-status-darwin-arm64` |
| macOS | Intel | `claude-status-darwin-amd64` |
| Linux | x86_64 | `claude-status-linux-amd64` |
| Linux | ARM64 | `claude-status-linux-arm64` |
| Windows | x86_64 | `claude-status-windows-amd64.exe` |

```bash
curl -L https://github.com/oscarangulo/claude-status/releases/latest/download/claude-status-darwin-arm64 -o claude-status
chmod +x claude-status
./claude-status install
```

### From source

```bash
git clone https://github.com/oscarangulo/claude-status.git
cd claude-status
make install
claude-status install
```

### Requirements

- [Claude Code](https://docs.anthropic.com/en/docs/claude-code)
- [jq](https://jqlang.github.io/jq/) (installed automatically with Homebrew)
- bash and awk (included in macOS, Linux, and Windows Git Bash)

---

## FAQ

**Does it slow down Claude Code?**
No. Each hook runs in under 50ms. You won't notice it.

**Does it send my data anywhere?**
No. Everything stays in `~/.claude-status/`. Zero network calls.

**What plan mode should I use?**
If you're on Claude Pro, Max, or Team — use the default (pro mode). If you pay per token via the API, switch to `--plan api` for cost tracking.

**Can I change how often the pulse appears?**
Yes. `claude-status budget --pulse 5` shows it every 5 interactions. Default is 3.

**Does it work on Windows?**
Yes. Install via `go install` or download the binary. Hooks use bash and awk, both included in Git Bash.

**How do I update?**
`claude-status update` or `brew upgrade claude-status`.

**How do I remove it?**
`claude-status uninstall` — choose to remove hooks only, hooks + data, or everything.

---

## Pricing reference

Cost is computed using official Anthropic pricing (per million tokens):

| | Input | Output | Cache Read | Cache Write |
|---|---:|---:|---:|---:|
| **Opus 4.6** | $5.00 | $25.00 | $0.50 | $6.25 |
| **Sonnet 4.6** | $3.00 | $15.00 | $0.30 | $3.75 |
| **Haiku 4.5** | $1.00 | $5.00 | $0.10 | $1.25 |

Context window sizes:

| Model | Context Window |
|---|---:|
| **Opus 4.6** | 1,000,000 tokens |
| **Sonnet 4.6** | 200,000 tokens |
| **Haiku 4.5** | 200,000 tokens |

---

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md).

## License

[MIT](LICENSE)
