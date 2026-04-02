# Claude Island

## Project Overview

Claude Island is a macOS native menu bar application that monitors multiple Claude Code Agent sessions running across any terminal (VS Code, iTerm2, Terminal.app, Warp, etc.) and displays their status via a pseudo-Dynamic Island UI, menu bar popover, and system notifications.

## Tech Stack

- **Language:** Swift 6
- **UI Framework:** SwiftUI + AppKit (for NSWindow / NSStatusBar)
- **Minimum Target:** macOS 14.0 (Sonoma)
- **Build System:** Xcode / Swift Package Manager
- **Architecture:** MVVM + three-layer (UI → Core Controller → State Collector)

## Key Design Decision

**State acquisition uses Claude Code Hooks** (configured in `~/.claude/settings.json`), NOT terminal output parsing. Hooks provide structured JSON events via stdin for:
- `Stop` — task completed
- `PermissionRequest` — tool permission needed
- `PreToolUse` (AskUserQuestion) — question for user

Session lifecycle tracking uses FSEvents file watching on `~/.claude/sessions/`.

## Project Structure

```
ClaudeIsland/
├── ClaudeIslandApp/              # macOS menu bar app
│   ├── App/                      # App entry, lifecycle, menu bar setup
│   ├── UI/
│   │   ├── MenuBar/              # NSStatusItem + NSPopover
│   │   ├── DynamicIsland/        # Floating window (pseudo-DI)
│   │   └── Settings/             # Preferences window
│   ├── Core/
│   │   ├── SessionManager.swift  # Global session registry (Actor)
│   │   ├── NotificationManager.swift
│   │   └── HookInstaller.swift   # Auto-setup hooks in settings.json
│   └── Collectors/
│       ├── FileWatcher.swift     # FSEvents on ~/.claude/sessions/
│       ├── HookReceiver.swift    # Unix Domain Socket server
│       └── ProcessMonitor.swift  # kill(pid, 0) liveness checks
├── Resources/
│   └── hooks/                    # Hook scripts bundled with app
│       ├── on-stop.sh
│       ├── on-permission.sh
│       └── on-question.sh
├── Shared/
│   ├── SessionModel.swift
│   └── HookEvent.swift
└── Tests/
```

## Key Data Sources

### Claude Code Session Files
Location: `~/.claude/sessions/{pid}.json`
```json
{
  "pid": 60717,
  "sessionId": "9444372a-...",
  "cwd": "/path/to/workspace",
  "startedAt": 1775070988321,
  "kind": "interactive",
  "entrypoint": "claude-vscode"
}
```

### Claude Code Hooks
Configured in: `~/.claude/settings.json` under `hooks` key.
Events: `Stop`, `PermissionRequest`, `PreToolUse`.
Data delivery: structured JSON via stdin to hook command.

### IPC
Unix Domain Socket at `/tmp/claude-island.sock`. NDJSON protocol.

## Development Commands

```bash
# Build the app
xcodebuild -scheme ClaudeIsland -configuration Debug build

# Run tests
xcodebuild -scheme ClaudeIsland test

# Format code
swift format --in-place --recursive Sources/
```

## Code Conventions

- Use Swift concurrency (async/await, actors) for all async work
- Use @Observable (Observation framework) for state management, not Combine
- Prefer value types (struct/enum) over reference types
- Keep UI layer thin — business logic in Core/
- Error handling: use typed errors, never force-unwrap in production
- Follow Swift API Design Guidelines for naming
- Hook scripts must execute in <50ms to avoid blocking Claude Code

## Important Notes

- Hook installation must MERGE with existing hooks, never replace
- Support coexistence with Claude Notifier, Vibe Island, etc.
- Always verify process liveness before showing session as "running"
- PID reuse: cross-check pid + startedAt timestamp

## Reference
- See DEVELOPMENT.md for full architecture and design documentation
- Competitive reference: https://vibeisland.app/ (Vibe Island, $19.99)
