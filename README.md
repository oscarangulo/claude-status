<p align="center">
  <img src="logo.png" alt="Claude Status" width="200">
  <h1 align="center">claude-status</h1>
  <p align="center">
    <strong>Stop burning money on Claude Code.</strong>
  </p>
  <p align="center">
    <a href="https://github.com/oscarangulo/claude-status/releases"><img src="https://img.shields.io/github/v/release/oscarangulo/claude-status" alt="Release"></a>
    <a href="https://github.com/oscarangulo/claude-status/actions"><img src="https://github.com/oscarangulo/claude-status/actions/workflows/ci.yml/badge.svg" alt="CI"></a>
    <a href="LICENSE"><img src="https://img.shields.io/github/license/oscarangulo/claude-status" alt="License"></a>
  </p>
</p>

---

**You've been there.** You finish a Claude Code session, type `/cost`, and see $45. A task that should have cost $5 turned into a money pit because Claude got stuck in a loop, your context overflowed, or you just didn't notice the meter running.

**claude-status makes that impossible.** It watches your spending in real-time and warns you *inside the conversation* before things get expensive. No dashboard to check. No extension to open. The warning comes to you.

```
[claude-status] BUDGET WARNING: Daily spend $16.40 is 82% of your $20 daily limit.
```

```
[claude-status] Loop detected: 4 failed Bash calls in a row.
               Consider explaining the issue instead of retrying.
```

```
[claude-status] Expensive session: $12.40 is 2.0x your average ($6.20).
               Consider splitting into smaller tasks.
```

<p align="center">
  <strong>Works in CLI and VS Code. Zero configuration after install.</strong>
</p>

## Install in 30 seconds

```bash
brew install oscarangulo/claude-status/claude-status
claude-status budget 20
```

Restart Claude Code. Done. You're protected.

> No Homebrew? See [other install options](#installation).

---

## Why you need this

| Without claude-status | With claude-status |
|---|---|
| Check `/cost` manually and hope you remember | Get warned at 50%, 80%, 100% of your budget automatically |
| Claude retries a failing command 10 times silently | Alert after 3 failures: *"Loop detected, stop retrying"* |
| Context fills up, Claude forgets your conversation | Warning at 80%: *"Use /compact soon"* |
| Use Opus for simple file reads at $5/M tokens | Suggestion: *"Use Sonnet for reads, save 70%"* |
| Realize at end of day you spent $60 | Daily/weekly reports with per-session breakdown |
| Each session costs differently, no pattern visibility | Alert when a session costs 2x your average |
| Start a plan with no idea what it'll cost | Estimate before you build: *"5 tasks × $2.88 = ~$14.40"* |

---

## Works Everywhere

claude-status uses Claude Code's `PostToolUse` hooks — part of the core engine, not the IDE. This means alerts work identically in:

- **Claude Code CLI** (terminal)
- **VS Code** (Claude Code extension)
- **Cursor**
- **JetBrains** (IntelliJ, WebStorm, etc.)

If Claude Code runs there, claude-status works there. No extra setup per IDE.

---

## 10 Smart Alerts + Plan Cost Estimation

Every alert appears **inside your conversation** as a system reminder. Claude sees it too and can react.

### Budget Protection

Set a daily limit. Get warned before you blow it.

```bash
claude-status budget 20         # alerts at $10, $16, and $20
claude-status budget --session 5  # per-session limit too
```

> `Daily spend $10.00 is 50% of $20 limit`
>
> `BUDGET WARNING: $16.40 is 82% of $20 limit`
>
> `BUDGET EXCEEDED: $22.50 has passed your $20 limit`

### Loop Detection

Claude gets stuck retrying a failing command? You'll know after 3 failures instead of 30.

> `Loop detected: 4 failed Bash calls in a row. Consider explaining the issue instead of retrying.`

**This one alert alone can save you $10+ per stuck session.**

### Expensive Session Alert

Your sessions have an average cost. When one session hits 2x that average, you get a heads up.

> `Expensive session: $12.40 is 2.0x your average ($6.20). Consider splitting into smaller tasks.`

### Model Suggestion

Running Opus ($5/M input) to read files? That's like taking a Ferrari to the grocery store.

> `Light tasks detected (reads/searches). Consider using Sonnet for this work to save ~70% on costs.`

### Context Watchdog

When your context window fills up, Claude starts losing earlier parts of the conversation. You want to `/compact` before that happens.

> `Context window at 80%. Consider using /compact soon.`
>
> `CONTEXT CRITICAL (92%): Use /compact NOW or risk losing conversation history.`

### Burn Rate Warning

Spending $0.50+ per minute? Something's off.

> `High burn rate: $0.65/min. Consider breaking tasks into smaller pieces.`

### Idle Context Warning

Context is high and you haven't done anything for 10 minutes? Start fresh.

> `Context at 75% with 15min idle. Consider starting a new session to save tokens.`

### Plan Cost Estimation

When Claude creates a plan (3+ tasks), you get an instant cost estimate before any work begins:

> `Plan estimate: 5 tasks × $2.88 avg = ~$14.40. Budget remaining: $25.60. This plan fits within your daily limit.`

Or if it's going to blow your budget:

> `Plan estimate: 8 tasks × $2.88 avg = ~$23.04. WARNING: This may exceed your remaining budget ($15.00). Consider splitting into phases or using Sonnet.`

The estimate is based on your historical average cost per completed task. The more tasks you complete, the more accurate it gets.

---

## Spending Reports

### Daily

```bash
claude-status report
```

```
═══════════════════════════════════════════
  Daily Report — 2026-04-01
═══════════════════════════════════════════

  Total spent:    $23.03
  Budget:         $20.00 (115% used)
  Sessions:       3
  Tasks:          8

  Avg cost/task:  $2.88
  Avg cost/sess:  $7.68
  Cache hit:      50%

  Tip: Close to daily limit. Use Sonnet/Haiku for lighter tasks.
═══════════════════════════════════════════
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
═══════════════════════════════════════════
  Total:           $76.11   Avg/day: $15.22
```

### TUI Dashboard

Run `claude-status` with no arguments for a real-time terminal dashboard:

- Budget progress bar with remaining amount
- Context window usage
- Token breakdown (input, output, cache hit rate)
- Per-task cost when using plans
- Optimization tips

---

## How It Works

```
You use Claude Code normally
         |
         v
Every tool call triggers snapshot-hook.sh (< 50ms)
         |
         v
Hook reads your native session data (~/.claude/projects/...)
         |
         v
Computes cost, checks thresholds, detects patterns
         |
         v
If threshold crossed --> alert appears in your conversation
If nothing wrong     --> silent, zero interruption
```

**That's it.** No background processes. No external services. No data leaves your machine.

Three hooks do all the work:

| Hook | What it does |
|------|-------------|
| **snapshot-hook.sh** | The brain. Reads session data, computes cost, runs all 9 alert checks, outputs warnings via `additionalContext` |
| **task-hook.sh** | Tracks per-task cost when you use plans (TodoWrite) |
| **status-line.sh** | Terminal status bar in CLI mode |

Alerts use Claude Code's `additionalContext` output — they appear as system reminders that both you and Claude can see. This works identically in **CLI** and **VS Code**.

---

## Commands

| Command | What it does |
|---------|-------------|
| `claude-status` | TUI dashboard |
| `claude-status budget 20` | Set $20/day daily limit |
| `claude-status budget --session 5` | Set $5/session limit |
| `claude-status budget` | Show current budget |
| `claude-status budget 0` | Disable budget |
| `claude-status report` | Today's spending |
| `claude-status report --week` | This week's spending |
| `claude-status history` | All past sessions |
| `claude-status install` | Set up hooks (auto on brew) |
| `claude-status update` | Upgrade + refresh hooks |
| `claude-status uninstall` | Clean removal |

---

## Installation

### Option 1: Homebrew (recommended)

```bash
brew install oscarangulo/claude-status/claude-status
```

Hooks configure automatically. Just restart Claude Code.

### Option 2: Go install

```bash
go install github.com/oscarangulo/claude-status/cmd/claude-status@latest
claude-status install
```

### Option 3: Download binary

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

### Option 4: From source

```bash
git clone https://github.com/oscarangulo/claude-status.git
cd claude-status
make install
claude-status install
```

### Requirements

- [Claude Code](https://docs.anthropic.com/en/docs/claude-code)
- [jq](https://jqlang.github.io/jq/) (installed automatically with Homebrew)

---

## Pricing Reference

Cost is computed using official Anthropic pricing (per million tokens):

| | Input | Output | Cache Read | Cache Write |
|---|---:|---:|---:|---:|
| **Opus 4.6** | $5.00 | $25.00 | $0.50 | $6.25 |
| **Sonnet 4.6** | $3.00 | $15.00 | $0.30 | $3.75 |
| **Haiku 4.5** | $1.00 | $5.00 | $0.10 | $1.25 |

---

## FAQ

**Does it slow down Claude Code?**
No. Each hook runs in under 50ms. You won't notice it.

**Does it send my data anywhere?**
No. Everything stays in `~/.claude-status/`. Zero network calls.

**Does it work in VS Code?**
Yes. Alerts use `PostToolUse` hooks which work in both CLI and VS Code.

**Can I use it without setting a budget?**
Yes. Loop detection, context warnings, model suggestions, and burn rate alerts work without any budget configured.

**How do I update?**
`claude-status update` or `brew upgrade claude-status`.

**How do I remove it?**
`claude-status uninstall` gives you options: remove hooks only, hooks + data, or everything.

---

## VS Code Extension

Want cost info in your IDE status bar too? See **[claude-status-vs-extension](https://github.com/oscarangulo/claude-status-vs-extension)**.

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md). Help wanted:

- Windows testing ([#3](https://github.com/oscarangulo/claude-status/issues/3))
- Per-subagent cost tracking ([#4](https://github.com/oscarangulo/claude-status/issues/4))

## License

[MIT](LICENSE)
