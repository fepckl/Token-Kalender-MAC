# TokenCalender – Mac

A native macOS app (SwiftUI, macOS 14+) that shows how many **Claude Code tokens** you used per day in a calendar.
macOS port of the token calendar from [TokenCalender](https://github.com/fepckl/TokenCalender) (Windows).

## Features
- **Month heatmap:** the darker the orange, the more tokens; square-root scale so busy days don't wash out the quiet ones
- **Details per day:** input, output, cache writes and cache reads, number of responses, breakdown by model
- **Toggle "Ohne Cache-Lesen"** (excl. cache reads): cache reads make up the bulk of the volume but count much less toward the limit
- **Menu bar item** with today's tokens; the calendar opens from the menu
- Rescans automatically every 5 minutes; light/dark mode; German/English
- Keys: arrows = day, PgUp/PgDn = month, ⌘R = rescan

## Data source
Claude Code's local transcripts: `~/.claude/projects/**/*.jsonl` (also `~/.config/claude/projects` and `CLAUDE_CONFIG_DIR`).
Each response is counted only once (message ID + request ID), because Claude Code writes the same token count on several lines and resumed sessions copy older messages.
Only Claude Code usage shows up; chats on claude.ai or in the desktop app aren't stored locally.

## Installation
**Download:** *Actions* → latest *macOS build* run → artifact `TokenCalendar-mac` → unzip → move `TokenCalendar.app` to *Applications*.

The app is only ad-hoc signed (no Apple developer account), so on first launch right-click → *Open*, or:
```bash
xattr -dr com.apple.quarantine /Applications/TokenCalendar.app
```

## Build it yourself
Requires Xcode or the Command Line Tools (Swift 5.9+):
```bash
bash scripts/bundle.sh   # → build/TokenCalendar.app (universal: Apple Silicon + Intel)
swift run                # or start directly without an .app bundle
```
