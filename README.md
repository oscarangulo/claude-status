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

## Installation

Install the CLI tool globally using Go:

```bash
go install github.com/oscarangulo/claude-status@latest
```

Then, simply run `claude-status` in your terminal or follow the [IDE Extension](#vs-code--cursor-extension) instructions to integrate it into your editor.

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

The cost shown in the status bar comes di