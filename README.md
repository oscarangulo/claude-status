<p align="center">
  <img src="logo.png" alt="Claude Status" width="200">
  <h1 align="center">claude-status</h1>
  <p align="center">
    <strong>Real-time token usage and cost monitoring for <a href="https://docs.anthropic.com/en/docs/claude-code">Claude Code</a></strong>
  </p>
  <p align="center">
    Know exactly where your tokens go. Track costs per task. Save money with cache insights.
  </p>
  <p align="center">
    <a href="https://marketplace.visualstudio.com/items?itemName=OscarAngulo.claude-status"><img src="https://img.shields.io/visual-studio-marketplace/v/OscarAngulo.claude-status?label=VS%20Code%20Marketplace" alt="VS Code Marketplace"></a>
    <a href="https://marketplace.visualstudio.com/items?itemName=OscarAngulo.claude-status"><img src="https://img.shields.io/visual-studio-marketplace/i/OscarAngulo.claude-status?label=installs" alt="Installs"></a>
    <a href="https://github.com/oscarangulo/claude-status/releases"><img src="https://img.shields.io/github/v/release/oscarangulo/claude-status" alt="Release"></a>
    <a href="https://github.com/oscarangulo/claude-status/actions"><img src="https://github.com/oscarangulo/claude-status/actions/workflows/ci.yml/badge.svg" alt="CI"></a>
    <a href="LICENSE"><img src="https://img.shields.io/github/license/oscarangulo/claude-status" alt="License"></a>
  </p>
  <p align="center">
    <a href="#installation">Install</a> ·
    <a href="#what-it-shows">Features</a> ·
    <a href="#how-costs-are-calculated">Pricing</a> ·
    <a href="#vs-code--cursor-extension">IDE Extension</a> ·
    <a href="#contributing">Contribute</a>
  </p>
</p>

---

See exactly where your tokens go — directly in Claude Code's status bar and your IDE. No extra terminal, no browser, no setup friction.

```
$0.3500 | 91.0K (in:45.0K out:12.0K) | 0.035/min | 10m0s | +210/-15
[###-------] 34% | cache:43% | saved $0.1575
> Implement auth system $0.0847
```

## What it shows

### Line 1 — Cost & Tokens
| Segment | Meaning |
|---------|---------|
| `$0.3500` | Total session cost (green < $0.50, yellow < $1, red > $1) |
| `91.0K` | Total tokens with input/output breakdown |
| `(in:45K out:12K)` | Input vs output tokens — output costs 5x more |
| `0.035/min` | Burn rate — your spending speed (colored by intensity) |
| `10m0s` | Session wall time |
| `+210/-15` | Lines of code added (green) / removed (red) |

### Line 2 — Context & Cache
| Segment | Meaning |
|---------|---------|
| `[###-------] 34%` | Context window usage bar (green/yellow/red) |
| `!!` | Danger alert when context > 80% — use `/compact` |
| `cache:43%` | Cache hit rate (green > 50%, yellow > 20%, red < 20%) |
| `saved $0.1575` | Money saved by prompt caching |

### Line 3 — Current Task
| Segment | Meaning |
|---------|---------|
| `> Implement auth system` | Active task from your plan (magenta) |
| `$0.0847` | Cost accumulated on this specific task (cyan) |

## How costs are calculated

### The `total_cost_usd` field

The cost shown in the status bar comes directly from Claude Code's `total_cost_usd` field. This is the **actual API cost**, not an estimate — it's calculated server-side from the real token counts returned by each API call, including all cache discounts. We don't recalculate the total.

### What we calculate ourselves

claude-status uses the official pricing to calculate two additional metrics:

1. **Cache savings** — how much money prompt caching saved you:
   ```
   savings = cache_read_tokens × (input_price - cache_read_price)
   ```
   Example (Opus): 35,000 cache reads = 35K × ($5.00 - $0.50) / 1M = **$0.1575 saved**

2. **Burn rate** — your spending speed:
   ```
   burn_rate = total_cost / session_duration_minutes
   ```

### Pricing per model (per million tokens)

| | Input | Output | Cache Write (5min) | Cache Write (1hr) | Cache Read |
|---|---:|---:|---:|---:|---:|
| **Opus 4.6** | $5.00 | $25.00 | $6.25 | $10.00 | $0.50 |
| **Sonnet 4.6** | $3.00 | $15.00 | $3.75 | $6.00 | $0.30 |
| **Haiku 4.5** | $1.00 | $5.00 | $1.25 | $2.00 | $0.10 |

### Example breakdown (Opus, single turn)

| Type | Tokens | Price/MTok | Cost |
|------|-------:|-----------:|-----:|
| Input | 45,000 | $5.00 | $0.2250 |
| Output | 12,000 | $25.00 | $0.3000 |
| Cache read | 35,000 | $0.50 | $0.0175 |
| Cache write | 8,000 | $6.25 | $0.0500 |
| **Total** | | | **$0.5925** |
| Cache savings | | | **$0.1575** |

> The cache savings represent what those 35K cache reads would have cost at full input price ($0.175) minus what they actually cost ($0.0175).

### Key insights

- **Output tokens cost 5x more than input** — that's why `in:` vs `out:` is shown separately. A task that generates a lot of code costs more than one that reads a lot of files.
- **Cache reads are 10x cheaper than fresh input** — a high cache hit rate means significant savings. Structured, consistent prompts maximize cache reuse.
- **The `saved` amount** shows real dollars saved. If your cache hit rate is 80%, you're paying 10x less for 80% of your input tokens.
- **Burn rate** (`$/min`) lets you gauge if a task is worth continuing or if you should change approach. High burn rate = consider breaking the task into smaller pieces.

### Per-task cost tracking

When you use plans (TodoWrite), claude-status captures a cost snapshot when each task starts and completes. The delta gives you the exact cost of each task:

```
task_cost = cost_at_completion - cost_at_start
```

This lets you compare tasks: "Auth took $0.08, but Tests took $0.15 — maybe I should break up test tasks."

### Limitations

- Cache write prices assume the 5-minute TTL. The 1-hour TTL is more expensive but Claude Code doesn't expose which TTL is used.
- Cost per task is approximate — the snapshot is taken when the hook fires, which may be slightly after the actual API call.

## How it works

claude-status hooks into two Claude Code extension points:

1. **Status line** — runs after every message, captures token/cost data, shows colored inline display
2. **Task hooks** — captures when plan tasks start/complete to calculate per-task cost

```
Claude Code ──status line──> colored display + JSONL snapshot
             ──hooks───────> task lifecycle events + cost deltas
```

All data is stored locally in `~/.claude-status/sessions/`. Nothing is sent anywhere.

## Installation

### Requirements

- [Claude Code](https://docs.anthropic.com/en/docs/claude-code) installed
- [jq](https://jqlang.github.io/jq/) — JSON processor used by hook scripts
- [Go 1.22+](https://go.dev/dl/) (only for building from source)

### Option 1: Homebrew (macOS / Linux)

```bash
brew tap oscarangulo/claude-status
brew install claude-status
claude-status install
```

> Homebrew compiles from source, installs `jq` as a dependency, and puts the binary in your PATH automatically.

### Option 2: Quick install (Go users)

The fastest way if you have Go installed. The binary goes straight to your PATH — no extra steps.

```bash
go install github.com/oscarangulo/claude-status/cmd/claude-status@latest
claude-status install
```

> `go install` places the binary in `$GOPATH/bin` (usually `~/go/bin`), which is already in your PATH if Go is set up correctly. You can verify with `go env GOPATH`.

### Option 2: From source

Clone, build, and install to your PATH in one step:

```bash
git clone https://github.com/oscarangulo/claude-status.git
cd claude-status
make install            # builds + copies to ~/.local/bin + adds to PATH
claude-status install   # configures Claude Code hooks
```

> `make install` places the binary in `~/.local/bin` and automatically adds it to your PATH (updates `.zshrc` or `.bashrc` if needed). Open a new terminal or run `source ~/.zshrc` for the PATH change to take effect.

### Option 3: Download binary

Download pre-built binaries from [Releases](https://github.com/oscarangulo/claude-status/releases). No Go required.

| OS | Architecture | Binary |
|----|-------------|--------|
| macOS | Apple Silicon (M1+) | `claude-status-darwin-arm64` |
| macOS | Intel | `claude-status-darwin-amd64` |
| Linux | x86_64 | `claude-status-linux-amd64` |
| Linux | ARM64 | `claude-status-linux-arm64` |
| Windows | x86_64 | `claude-status-windows-amd64.exe` |

```bash
# Example: macOS Apple Silicon
curl -L https://github.com/oscarangulo/claude-status/releases/latest/download/claude-status-darwin-arm64 -o claude-status
chmod +x claude-status
# Move to a directory in your PATH:
mv claude-status ~/.local/bin/   # or /usr/local/bin/ with sudo
claude-status install
```

### What `install` does

1. Copies hook scripts to `~/.claude-status/hooks/`
2. Configures `~/.claude/settings.json` with status line and hooks
3. Creates a backup of your existing settings

Restart Claude Code after installing.

### Where does the binary go?

| Method | Binary location | In PATH? |
|--------|----------------|----------|
| Homebrew | `/opt/homebrew/bin/claude-status` | Yes (managed by brew) |
| `go install` | `~/go/bin/claude-status` | Yes (if Go is set up) |
| `make install` | `~/.local/bin/claude-status` | Yes (auto-configured) |
| Download binary | Wherever you put it | You choose |

## Platform support

| Platform | Status | Notes |
|----------|--------|-------|
| macOS | Fully supported | Tested on Apple Silicon and Intel |
| Linux | Fully supported | Any distro with bash and jq |
| Windows (WSL) | Supported | Claude Code runs in WSL with full bash |
| Windows (Git Bash) | Supported | Hook scripts work in Git Bash |

## Commands

```bash
claude-status install     # Configure hooks in Claude Code
claude-status update      # Update hooks after upgrading the binary
claude-status uninstall   # Remove hooks (keeps session data)
claude-status             # TUI dashboard (optional, extra terminal)
claude-status history     # Show past session cost summaries
claude-status --version   # Show installed version
```

## Updating

When a new version is released, update the binary and then run `update` to refresh the hook scripts:

### If installed with Homebrew

```bash
brew upgrade claude-status
claude-status update
```

### If installed with `go install`

```bash
go install github.com/oscarangulo/claude-status/cmd/claude-status@latest
claude-status update
```

### If installed from source

```bash
cd claude-status
git pull
make install
claude-status update
```

### If using a downloaded binary

```bash
# Download the new binary (same as install)
curl -L https://github.com/oscarangulo/claude-status/releases/latest/download/claude-status-darwin-arm64 -o claude-status
chmod +x claude-status
./claude-status update
```

`update` re-extracts the hook scripts from the binary and updates `~/.claude/settings.json`. Your session data is preserved. Restart Claude Code after updating.

> **Why is `update` needed?** The status line and task hooks are bash scripts that live in `~/.claude-status/hooks/`. When you upgrade the binary, the new scripts are embedded inside it but not yet copied to disk. `update` (or `install`) copies them.

## Uninstalling

```bash
claude-status uninstall        # Remove hooks from Claude Code
rm -rf ~/.claude-status        # Optionally remove all data
```

## Data storage

```
~/.claude-status/
  hooks/            # Installed hook scripts
  sessions/         # JSONL logs (one file per session)
```

Each session file contains:
- **Snapshots** — token counts, costs, context usage, model (after each message)
- **Task events** — task started/completed with cost snapshot for delta calculation

## VS Code / Cursor Extension

<a href="https://marketplace.visualstudio.com/items?itemName=OscarAngulo.claude-status"><img src="https://img.shields.io/visual-studio-marketplace/v/OscarAngulo.claude-status?label=VS%20Code%20Marketplace&logo=visual-studio-code" alt="VS Code Marketplace"></a>

See your Claude Code costs directly in your IDE status bar — no terminal needed.

**Install from Marketplace:**
```bash
# VS Code
ext install OscarAngulo.claude-status

# Or search "Claude Status Monitor" in the Extensions tab
```

Or install directly: **[Claude Status Monitor on VS Code Marketplace](https://marketplace.visualstudio.com/items?itemName=OscarAngulo.claude-status)**

**What you get:**
- **Status bar line 1:** cost, tokens (in/out), burn rate, duration, lines changed
- **Status bar line 2:** context %, cache hit rate, savings, current task
- **Click** for a detailed breakdown panel with per-task costs
- **Hover** for a rich tooltip with full metrics
- Auto-updates every 5 seconds via file watcher

Works with **VS Code**, **Cursor**, and **VS Code Insiders**. The extension reads the same `~/.claude-status/sessions/` data generated by the hooks — no additional setup needed.

## Optimization tips (TUI)

The TUI dashboard (`claude-status` with no args) includes an optimization engine:

- **Low cache hit rate** — restructure prompts for better caching
- **High context usage** — use `/compact` before it overflows
- **Expensive tasks** — break large tasks into smaller, cheaper ones
- **Low output/input ratio** — use targeted reads instead of broad searches
- **High cost per line** — parallelize with subagents

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md). Areas where help is welcome:

- Windows testing ([#3](https://github.com/oscarangulo/claude-status/issues/3))
- Per-subagent cost tracking ([#4](https://github.com/oscarangulo/claude-status/issues/4))
- Budget alerts ([#5](https://github.com/oscarangulo/claude-status/issues/5))
- Publish extension to VS Code Marketplace

## License

[MIT](LICENSE)
