<p align="center">
  <img src="icon.png" alt="Claude Status Monitor" width="128">
  <h1 align="center">Claude Status Monitor</h1>
  <p align="center">
    <strong>Real-time token usage and cost monitoring for Claude Code</strong>
  </p>
  <p align="center">
    See exactly where your tokens go — directly in your VS Code / Cursor status bar.
  </p>
</p>

---

## Features

### Status Bar (always visible)

**Line 1 — Cost & Tokens**
- Total session cost (color-coded: green < $0.50, yellow < $1, red > $1)
- Token count with input/output breakdown
- Burn rate ($/min) — your spending speed
- Session duration
- Lines of code changed (+added/-removed)

**Line 2 — Context & Cache**
- Context window usage with warning at 80%
- Cache hit rate (higher = cheaper)
- Money saved by prompt caching
- Current task name and its cost

### Click for Details

Click the status bar for a detailed breakdown panel showing:
- Full cost and token metrics
- Per-task cost history
- Cache savings
- Context usage

### Hover Tooltip

Hover over the status bar for a rich markdown tooltip with:
- Model name
- Cost table (total, burn rate, duration)
- Token breakdown (input, output, cache read/write)
- Context usage bar
- Current task progress

## Requirements

1. **Claude Code** installed and running
2. **claude-status hooks** configured — install via CLI:

```bash
# Install the CLI tool (any method)
go install github.com/oscarangulo/claude-status/cmd/claude-status@latest
# Or: brew tap oscarangulo/claude-status && brew install claude-status

# Configure hooks in Claude Code
claude-status install
```

3. Restart Claude Code after installing hooks

> The hooks capture token/cost data from Claude Code sessions. This extension reads that data and displays it in your IDE. No additional configuration needed.

## How it works

```
Claude Code ──hooks──> ~/.claude-status/sessions/*.jsonl
                                    │
                          VS Code Extension reads ──> Status Bar
```

1. Claude Code hooks capture token/cost snapshots after every message
2. Data is stored locally as JSONL files in `~/.claude-status/sessions/`
3. This extension watches those files and updates the status bar in real-time
4. Nothing is sent anywhere — all data stays on your machine

## Commands

| Command | Description |
|---------|-------------|
| `Claude Status: Show Session Details` | Open detailed breakdown panel |
| `Claude Status: Refresh` | Force refresh the status bar |

## Status bar icons

| Icon | Meaning |
|------|---------|
| ✓ | Cost under $0.50 — you're doing great |
| ⚠ | Cost between $0.50 and $1.00 |
| 🔥 | Cost over $1.00 — watch your spending |
| ▶ | A plan task is currently running |
| ⚠ (context) | Context window is over 80% — use `/compact` |

## Platform support

| IDE | Supported |
|-----|-----------|
| VS Code | ✓ |
| Cursor | ✓ |
| VS Code Insiders | ✓ |
| Windsurf | ✓ (untested) |

## Privacy

- All data is stored locally in `~/.claude-status/sessions/`
- No telemetry, no external API calls, no data collection
- The extension only reads local JSONL files on your machine

## Links

- [GitHub Repository](https://github.com/oscarangulo/claude-status)
- [Report Issues](https://github.com/oscarangulo/claude-status/issues)
- [CLI Documentation](https://github.com/oscarangulo/claude-status#readme)

## License

[MIT](https://github.com/oscarangulo/claude-status/blob/main/LICENSE)
