<p align="center">
  <img src="logo.png" alt="Claude Status" width="200">
  <h1 align="center">claude-status</h1>
  <p align="center">
    <strong>Smart cost guardian for <a href="https://docs.anthropic.com/en/docs/claude-code">Claude Code</a></strong>
  </p>
  <p align="center">
    Budget alerts, context warnings, and spending reports — delivered directly in your conversation.
  </p>
  <p align="center">
    <a href="https://github.com/oscarangulo/claude-status/releases"><img src="https://img.shields.io/github/v/release/oscarangulo/claude-status" alt="Release"></a>
    <a href="https://github.com/oscarangulo/claude-status/actions"><img src="https://github.com/oscarangulo/claude-status/actions/workflows/ci.yml/badge.svg" alt="CI"></a>
    <a href="LICENSE"><img src="https://img.shields.io/github/license/oscarangulo/claude-status" alt="License"></a>
  </p>
  <p align="center">
    <a href="#quick-start">Quick Start</a> ·
    <a href="#budget-alerts">Budget</a> ·
    <a href="#what-it-monitors">Features</a> ·
    <a href="#commands">Commands</a> ·
    <a href="#contributing">Contribute</a>
  </p>
</p>

---

claude-status watches your Claude Code spending and alerts you before things get expensive. No dashboard to check, no extension to open — warnings appear right in your conversation, in both CLI and VS Code.

```
[claude-status] BUDGET WARNING: Daily spend $16.40 is 82% of your $20 daily limit.
```

```
[claude-status] CONTEXT CRITICAL (92%): Use /compact NOW or risk losing conversation history.
```

```
[claude-status] High burn rate: $0.65/min. Consider breaking tasks into smaller pieces.
```

## Quick Start

```bash
# Install (hooks are configured automatically)
brew install oscarangulo/claude-status/claude-status

# Set a daily budget (optional)
claude-status budget 20

# Restart Claude Code — alerts start automatically
```

Set a spending limit and get warned before you blow it:

```bash
claude-status budget 30       # $30/day limit
claude-status budget --session 10  # $10/session limit
claude-status budget 0        # disable daily limit
```

## Budget Alerts

Set a spending limit and get warned before you blow it.

```bash
claude-status budget 20
```

| Alert | When | Example |
|-------|------|---------|
| Budget update | 50% of daily limit | `Daily spend $10.00 is 50% of $20 limit` |
| Budget warning | 80% of daily limit | `BUDGET WARNING: $16.40 is 82% of $20 limit` |
| Budget exceeded | 100% of daily limit | `BUDGET EXCEEDED: $22.50 has passed your $20 limit` |
| Session warning | 80% of session limit | `Session spend $4.20 is 84% of $5 session limit` |
| Session exceeded | 100% of session limit | `SESSION BUDGET EXCEEDED: $5.30, limit is $5` |

Alerts appear **once per threshold per session** — no spam.

### How alerts work

claude-status uses Claude Code's `additionalContext` hook output. When a threshold is crossed, the alert is injected into Claude's context as a system reminder. Claude sees it and can react — for example, suggesting cheaper alternatives or confirming before expensive operations.

This works identically in **CLI terminal** and **VS Code extension**.

### Budget configuration

```bash
# Set daily budget
claude-status budget 20

# Set per-session budget
claude-status budget --session 5

# Set both
claude-status budget 20 --session 5

# Check current budget
claude-status budget

# Disable
claude-status budget 0
```

Budget is stored in `~/.claude-status/budget.json`.

## What it Monitors

### Context Watchdog

Alerts before your context window overflows and Claude loses conversation history.

| Context % | Alert |
|-----------|-------|
| 80% | `Context window at 80%. Consider using /compact soon.` |
| 90% | `CONTEXT CRITICAL (90%): Use /compact NOW or risk losing conversation history.` |

### Burn Rate Detection

Warns when you're spending too fast.

| Condition | Alert |
|-----------|-------|
| > $0.50/min | `High burn rate: $0.65/min. Consider breaking tasks into smaller pieces.` |

### Per-Task Cost Tracking

When you use plans (TodoWrite), claude-status captures a cost snapshot when each task starts and completes:

```
task_cost = cost_at_completion - cost_at_start
```

Visible in the TUI dashboard and daily report.

## Commands

```bash
claude-status install           # Set up hooks + optional budget
claude-status budget [amount]   # Set daily limit (alerts at 50%, 80%, 100%)
claude-status budget --session N  # Set per-session limit
claude-status report            # Today's spending summary
claude-status                   # TUI dashboard (optional)
claude-status history           # Past session summaries
claude-status update            # Upgrade binary + refresh hooks
claude-status uninstall         # Interactive cleanup
```

### Daily Report

```bash
claude-status report
```

```
═══════════════════════════════════════════
  Daily Report — 2026-04-01
═══════════════════════════════════════════

  Total spent:    $23.0347
  Budget:         $20.00 (115% used, $-3.03 remaining)
  Sessions:       3
  Tasks:          8
  Model:          claude-opus-4-6

  Tokens:         34.1M total
  Cache hit:      50%

  Avg cost/task:  $2.8793
  Avg cost/sess:  $7.6782

  Tip: Close to daily limit. Use Sonnet/Haiku for lighter tasks.
═══════════════════════════════════════════
```

### TUI Dashboard

Run `claude-status` with no arguments to open the terminal dashboard. Shows real-time cost, tokens, context bar, per-task breakdown, and optimization tips.

## Installation

### Requirements

- [Claude Code](https://docs.anthropic.com/en/docs/claude-code) installed
- [jq](https://jqlang.github.io/jq/) — JSON processor used by hook scripts

### Option 1: Homebrew (macOS / Linux)

```bash
brew install oscarangulo/claude-status/claude-status
```

Hooks are configured automatically. Just restart Claude Code.

### Option 2: Go install

```bash
go install github.com/oscarangulo/claude-status/cmd/claude-status@latest
claude-status install
```

### Option 3: From source

```bash
git clone https://github.com/oscarangulo/claude-status.git
cd claude-status
make install
claude-status install
```

### Option 4: Download binary

Download from [Releases](https://github.com/oscarangulo/claude-status/releases):

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

### What `install` does

1. Ensures the `claude-status` binary is in your `PATH`
2. Copies hook scripts to `~/.claude-status/hooks/`
3. Configures `~/.claude/settings.json` with hooks
4. Asks you to set a daily budget (optional)
5. Creates a backup of your existing settings

Restart Claude Code after installing.

## How it Works

```
Claude Code ──PostToolUse──> snapshot-hook.sh ──> cost snapshot + alerts
             ──PostToolUse──> task-hook.sh    ──> per-task cost tracking
             ──statusLine───> status-line.sh  ──> terminal display (CLI only)
```

Three hooks, each with a specific job:

| Hook | Trigger | What it does |
|------|---------|-------------|
| `snapshot-hook.sh` | Every tool use | Reads native Claude Code data, writes cost snapshots, checks budget/context/burn rate, outputs alerts |
| `task-hook.sh` | TodoWrite | Tracks task start/complete for per-task cost |
| `status-line.sh` | After each response (CLI only) | Colored terminal status line |

All data is stored locally in `~/.claude-status/`. Nothing is sent anywhere.

## Updating

```bash
claude-status update
```

This upgrades the binary (if possible for your install method), refreshes hook scripts, and preserves your budget and session data.

## Uninstalling

```bash
claude-status uninstall
```

Choose what to remove:

- **setup** — Claude Code hooks only (keeps data and budget)
- **data** — setup + `~/.claude-status`
- **full** — setup + data + binaries + IDE extensions

## Pricing Reference

Cost calculations use official Anthropic pricing (per million tokens):

| | Input | Output | Cache Read | Cache Write (5min) |
|---|---:|---:|---:|---:|
| **Opus 4.6** | $5.00 | $25.00 | $0.50 | $6.25 |
| **Sonnet 4.6** | $3.00 | $15.00 | $0.30 | $3.75 |
| **Haiku 4.5** | $1.00 | $5.00 | $0.10 | $1.25 |

## VS Code / Cursor Extension

The VS Code extension shows cost data in your IDE status bar: **[claude-status-vs-extension](https://github.com/oscarangulo/claude-status-vs-extension)**

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md). Areas where help is welcome:

- Windows testing ([#3](https://github.com/oscarangulo/claude-status/issues/3))
- Per-subagent cost tracking ([#4](https://github.com/oscarangulo/claude-status/issues/4))

## License

[MIT](LICENSE)
