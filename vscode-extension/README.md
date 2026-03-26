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

**Line 1 — What you're spending**
```
Spent $0.3500 ($0.035/min) | 30m0s | 210 added, 15 removed
```
- How much you've spent and how fast
- Session duration
- Lines of code changed

**Line 2 — Memory and savings**
```
Memory 34% | Saved $0.1575 from cache
```
- How full Claude's memory is (warning at 80%)
- How much money cache saved you
- Current task and its cost

### Hover — Quick summary

```
Claude Opus 4.6 — Session cost: $0.4200
Spending $0.014 per minute
Reading 85.0K tokens, writing 22.0K tokens
Cache saved you $0.1800 (47% reused)
Click for full breakdown
```

### Click — Full breakdown

Click the status bar to see everything in a scrollable panel:
- Total spent and spending speed
- Tokens used (reading vs writing)
- Cache savings and reuse percentage
- Memory used (how much remaining)
- Code changes
- Current task with cost
- Completed tasks with individual costs

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
