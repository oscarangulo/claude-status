<p align="center">
  <h1 align="center">claude-status</h1>
  <p align="center">
    Real-time token usage and cost monitoring for <a href="https://docs.anthropic.com/en/docs/claude-code">Claude Code</a>
  </p>
  <p align="center">
    <a href="https://github.com/oscarangulo/claude-status/actions"><img src="https://github.com/oscarangulo/claude-status/actions/workflows/ci.yml/badge.svg" alt="CI"></a>
    <a href="https://github.com/oscarangulo/claude-status/releases"><img src="https://img.shields.io/github/v/release/oscarangulo/claude-status" alt="Release"></a>
    <a href="LICENSE"><img src="https://img.shields.io/github/license/oscarangulo/claude-status" alt="License"></a>
    <a href="https://goreportcard.com/report/github.com/oscarangulo/claude-status"><img src="https://goreportcard.com/badge/github.com/oscarangulo/claude-status" alt="Go Report Card"></a>
  </p>
</p>

---

See exactly where your tokens go — directly in Claude Code's status bar. No extra terminal, no browser, no setup friction.

```
$0.1847 | 91.0K tok | cache:43% | ██░░░ 48% | 6m32s | +210/-15 | ▸ Auth system $0.08
```

## What it shows

| Segment | Meaning |
|---------|---------|
| `$0.1847` | Total session cost |
| `91.0K tok` | Total tokens (input + output) |
| `cache:43%` | Cache hit rate — higher is better |
| `██░░░ 48%` | Context window usage with visual bar |
| `⚠` | Warning when context > 80% (use `/compact`) |
| `6m32s` | Session duration |
| `+210/-15` | Lines of code added/removed |
| `▸ Auth system $0.08` | Current task and its cost so far |

## How it works

claude-status hooks into two Claude Code extension points:

1. **Status line** — runs after every message, captures token/cost data and renders the inline display
2. **Task hooks** — captures when plan tasks start/complete to calculate per-task cost

```
Claude Code ──status line──> inline display + snapshot log
             ──hooks───────> task lifecycle events
```

All data is stored locally in `~/.claude-status/sessions/` as JSONL files. Nothing is sent anywhere.

## Installation

### Requirements

- [Claude Code](https://docs.anthropic.com/en/docs/claude-code) installed
- [jq](https://jqlang.github.io/jq/) — JSON processor used by hook scripts
- [Go 1.22+](https://go.dev/dl/) (only for building from source)

### Quick install

```bash
go install github.com/oscarangulo/claude-status/cmd/claude-status@latest
claude-status install
```

### From source

```bash
git clone https://github.com/oscarangulo/claude-status.git
cd claude-status
make build
./bin/claude-status install
```

### Download binary

Download pre-built binaries from [Releases](https://github.com/oscarangulo/claude-status/releases) for:

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
./claude-status install
```

### What `install` does

1. Copies hook scripts to `~/.claude-status/hooks/`
2. Configures `~/.claude/settings.json` with status line and hooks
3. Creates a backup of your existing settings

Restart Claude Code after installing.

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
claude-status uninstall   # Remove hooks (keeps session data)
claude-status             # TUI dashboard (optional, extra terminal)
claude-status history     # Show past session cost summaries
```

## Uninstalling

```bash
# Remove hooks from Claude Code settings
claude-status uninstall

# Optionally remove all data
rm -rf ~/.claude-status
```

Session data in `~/.claude-status/sessions/` is preserved by `uninstall` so you don't lose your history.

## Data storage

```
~/.claude-status/
  hooks/            # Installed hook scripts
  sessions/         # JSONL logs (one file per session)
```

Each session file contains two types of entries:

- **Snapshots** — token counts, costs, context usage (captured after each message)
- **Task events** — task started/completed with cost at that moment

## Optimization tips (built-in)

The TUI dashboard (`claude-status` with no args) includes an optimization tips engine:

- **Low cache hit rate** — suggests restructuring prompts
- **High context usage** — reminds you to use `/compact`
- **Expensive tasks** — flags tasks consuming disproportionate cost
- **Low output/input ratio** — suggests targeted file reads
- **High cost per line** — suggests using subagents

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) for guidelines. Areas where help is especially welcome:

- Windows testing
- New optimization heuristics
- Homebrew / AUR / Scoop packaging
- Per-tool-call cost tracking

## License

[MIT](LICENSE)
