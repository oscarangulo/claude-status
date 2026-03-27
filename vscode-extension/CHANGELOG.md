# Changelog

## 0.4.11 (2026-03-27)

- Align the VS Code extension release line with the CLI uninstall cleanup improvements in `v0.4.11`
- Keep Marketplace users on the latest release train while the CLI now removes `~/.local/bin` PATH entries and broader extension folder variants during full cleanup

## 0.4.10 (2026-03-27)

- Fix session selection so the VS Code extension ignores side sessions like Claude Mem observer logs and subagent JSONL files
- Pick the newest Claude Code session that actually contains usable assistant usage metrics instead of falling back to `waiting for next response`

## 0.4.9 (2026-03-27)

- Fix the VS Code extension so active Claude Code sessions show usage immediately even when `~/.claude-status/sessions` snapshots are empty
- Fall back to Claude Code's native `~/.claude/projects/**/*.jsonl` session history so existing and newly started sessions appear in the status bar
- Watch both managed snapshot files and native Claude Code project sessions for faster refreshes
- Make Marketplace setup install the `claude-status` CLI into `~/.local/bin` and add that directory to shell `PATH` when needed

## 0.4.8 (2026-03-27)

- Make CLI uninstall interactive so users can choose setup-only, data cleanup, or full local removal in one command
- Add non-interactive uninstall modes for scripts with `--mode` and `--yes`
- Update the VS Code extension uninstall flow to offer setup-only or setup-plus-data cleanup directly in the IDE
- Remove a duplicate runtime id assignment from the extension status hook template

## 0.4.7 (2026-03-27)

- Align the VS Code extension version with the latest Git and Homebrew release line
- Publish the extension on the same release train as the installer and self-update improvements
- No functional extension behavior changes beyond version synchronization

## 0.4.2 (2026-03-27)

- Make the CLI installer place `claude-status` on `PATH` when users install from a local binary, source checkout, or `go run`
- Clarify in the VS Code extension that Claude Code hooks can be configured automatically without separate CLI steps
- Fix the extension task hook template so task-instance ids are generated reliably during setup
- Improve onboarding copy when Claude Code needs a restart after setup
- Rename VS Code commands to reflect full Claude Code setup instead of only hook installation

## 0.4.1 (2026-03-27)

- Fix task tracking so repeated task names no longer merge into the same cost bucket
- Prevent duplicate task completion events from hooks and extension views
- Harden JSONL snapshot and task event writing using `jq`-generated JSON
- Keep the TUI focused on the active session instead of mixing multiple session files
- Align extension metrics with the CLI for cache hit rate and current-task detection
- Add the missing help toggle in the TUI

## 0.4.0 (2026-03-26)

- Add automatic hook install and uninstall flows from the extension
- Improve status bar detail lines and full session breakdown panel
- Refresh session data with file watching plus periodic polling
- Package the extension for Marketplace distribution

## 0.3.0 (2026-03-26)

- Rewrite all messages to be human-friendly and easy to understand
- Status bar: "Spent $0.35 ($0.035/min)" instead of "$0.35 | 0.035/min"
- Tooltip: plain sentences like "Spending $0.014 per minute"
- Details panel: "85.0K reading, 22.0K writing" instead of "in:85.0K out:22.0K"
- Context shown as "Memory 38%" with "62% remaining"
- Cache shown as "Saved $0.18 from cache" and "47% reused"
- Tasks shown as "Working on: Auth ($0.08 so far)"
- Fix icon size for marketplace (256x256, 103KB)
- Compact hover tooltip with "Click for full breakdown"

## 0.2.0 (2026-03-26)

- Initial release
- Status bar with cost, tokens, burn rate, duration, lines changed
- Context window usage with visual indicator and warning
- Cache hit rate and savings display
- Current task tracking with cost delta
- Click for detailed session breakdown panel
- Hover tooltip with full metrics in markdown
- Auto-refresh via file watcher + 5s polling
- Works with VS Code and Cursor
