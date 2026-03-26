# Changelog

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
