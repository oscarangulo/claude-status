# claude-status

Real-time token usage and cost dashboard for [Claude Code](https://docs.anthropic.com/en/docs/claude-code).

See exactly where your tokens go, how much each task in your plan costs, and get optimization tips — all in a live terminal dashboard.

```
╭──────────────────────────────────────────────────╮
│  Claude Status | Claude Opus 4.6                 │
│  Cost: $0.3200  Tokens: 125.3K  Duration: 6m32s │
╰──────────────────────────────────────────────────╯
╭──────────────────────────────────────────────────╮
│  Context: ████████████░░░░░░░░░░░░░░░░░░  34%   │
╰──────────────────────────────────────────────────╯
╭──────────────────────────────────────────────────╮
│  Token Breakdown                                 │
│    Input:       89.2K                            │
│    Output:      36.1K                            │
│    Cache Read:  45.0K                            │
│    Cache Write: 12.3K                            │
│    Cache Hit:   62%                              │
╰──────────────────────────────────────────────────╯
╭──────────────────────────────────────────────────╮
│  Plan Tasks                                      │
│  ✓ Setup proyecto base       $0.0300  ███░  9%   │
│  ✓ Modelo de usuarios        $0.0500  ████  16%  │
│  ✓ Endpoint login            $0.0800  █████ 25%  │
│  ● Tests e2e                 $0.1000  ██████ 31% │
╰──────────────────────────────────────────────────╯
╭──────────────────────────────────────────────────╮
│  Tips                                            │
│  • Cache hit rate: 62% — good prompt structure   │
│  • "Tests e2e" is the most expensive task (31%)  │
╰──────────────────────────────────────────────────╯
```

## Features

- **Real-time cost tracking** — see cumulative cost and token usage update live
- **Cost per task** — know exactly how much each step in your plan costs
- **Token breakdown** — input, output, cache reads, cache writes
- **Context window monitor** — visual progress bar with warnings
- **Cache hit rate** — understand how well prompt caching is working
- **Optimization tips** — actionable suggestions to reduce token spend
- **Session history** — review past sessions and compare costs

## How it works

claude-status uses two Claude Code extension points:

1. **Status line script** — captures token/cost snapshots after every message
2. **Hooks** — captures task lifecycle events (started, completed) from your plans

The Go TUI watches the log files and renders everything in real-time.

```
Claude Code ──status line──▶ snapshots.jsonl ──▶ ┌─────────────┐
             ──hooks──────▶ task events        ──▶ │ TUI Dashboard│
                                                   └─────────────┘
```

## Requirements

- [Claude Code](https://docs.anthropic.com/en/docs/claude-code) installed and configured
- [Go 1.22+](https://go.dev/dl/) (for building from source)
- [jq](https://jqlang.github.io/jq/) (for the hook scripts)

## Installation

### From source

```bash
go install github.com/oscarangulo/claude-status/cmd/claude-status@latest
```

### Build locally

```bash
git clone https://github.com/oscarangulo/claude-status.git
cd claude-status
make build
```

### Configure hooks

Run the installer to automatically configure Claude Code:

```bash
claude-status install
```

This will:
1. Copy hook scripts to `~/.claude-status/hooks/`
2. Update `~/.claude/settings.json` with status line and hook configuration
3. Create a backup of your existing settings

Then restart Claude Code.

## Usage

Open a **second terminal** alongside Claude Code and run:

```bash
claude-status
```

The dashboard updates in real-time as Claude Code works.

### Commands

| Command | Description |
|---------|-------------|
| `claude-status` | Launch live dashboard |
| `claude-status install` | Install hooks into Claude Code |
| `claude-status history` | Show past session summaries |

### Keyboard shortcuts

| Key | Action |
|-----|--------|
| `q` / `Ctrl+C` | Quit |
| `r` | Force refresh |
| `?` | Toggle help |

## Data storage

All data is stored locally in `~/.claude-status/`:

```
~/.claude-status/
  sessions/         # JSONL log files (one per session)
  hooks/            # Installed hook scripts
```

No data is sent anywhere. Everything stays on your machine.

## Contributing

Contributions welcome! This project is in early development.

```bash
git clone https://github.com/oscarangulo/claude-status.git
cd claude-status
make build
make test
```

## License

MIT
