# Claude Island — Development Documentation

## 1. Product Vision

Claude Island is a macOS native menu bar app that acts as a **command center** for all Claude Code Agent sessions running on your Mac. It provides real-time status monitoring, approval notifications, and session tracking — regardless of which terminal the Agent is running in.

### Target Users
- Developers who run multiple Claude Code sessions simultaneously
- Power users who work across VS Code, iTerm2, Terminal.app, and other terminals

### Core Value Proposition
- **Never miss an approval request** — get notified instantly when any Agent needs your input
- **Track all sessions at a glance** — menu bar icon shows active count, popover shows details
- **Terminal-agnostic** — works with VS Code integrated terminal, iTerm2, Terminal.app, Warp, tmux
- **Zero-config** — auto-installs hooks on first launch, no user setup required

### Competitive Reference: Vibe Island ($19.99)
- Supports 6 AI agents (Claude, Codex, Gemini, Cursor, OpenCode, Factory Droid)
- 13+ terminal precise jump support (including tmux)
- GUI-based permission approval (no need to switch to terminal)
- Plan preview with Markdown rendering
- 8-bit synth sound alerts
- Uses Claude Code Hooks (settings.json) for state acquisition — NOT terminal output parsing
- Native Swift, <50MB, macOS 14+

---

## 2. Architecture

### 2.1 Core Insight: Claude Code Hooks

**Critical design decision:** We use [Claude Code Hooks](https://docs.anthropic.com/en/docs/claude-code/hooks) as the primary state acquisition mechanism. This is the same approach used by Vibe Island.

Claude Code supports the following hook events:
- **`Stop`** — fires when Claude finishes a task or stops. Receives `{ transcript_path, stop_hook_active }` via stdin.
- **`PermissionRequest`** — fires when Claude needs permission to use a tool. Receives `{ tool_name }` via stdin.
- **`PreToolUse`** — fires before a tool is used. Can be filtered by tool name (e.g., `AskUserQuestion`).

Hooks are configured in `~/.claude/settings.json` and receive structured JSON data via stdin. This is far more reliable than parsing terminal output.

### 2.2 Three-Layer Design

```
┌──────────────────────────────────────────────────────────┐
│                    UI Layer (SwiftUI + AppKit)            │
│                                                          │
│  ┌────────────┐  ┌─────────────────┐  ┌───────────────┐ │
│  │ Menu Bar   │  │ Pseudo-Dynamic  │  │ System        │ │
│  │ Icon +     │  │ Island Window   │  │ Notifications │ │
│  │ Popover    │  │ (Floating)      │  │ (UNUserNotif) │ │
│  └─────┬──────┘  └───────┬─────────┘  └───────┬───────┘ │
│        │                 │                     │         │
├────────┴─────────────────┴─────────────────────┴─────────┤
│                Core Controller Layer                      │
│                                                          │
│  ┌─────────────────────────────────────────────────────┐ │
│  │  SessionManager (Actor)                             │ │
│  │  - Maintains global session registry                │ │
│  │  - Session lifecycle state machine                  │ │
│  │  - Publishes state changes via @Observable          │ │
│  ├─────────────────────────────────────────────────────┤ │
│  │  NotificationManager                                │ │
│  │  - Decides when to trigger DI / system notification │ │
│  │  - Handles notification action callbacks            │ │
│  └─────────────────────────────────────────────────────┘ │
│                                                          │
├──────────────────────────────────────────────────────────┤
│                State Collector Layer                      │
│                                                          │
│  ┌──────────────────┐  ┌──────────────────────────────┐ │
│  │ FileWatcher       │  │ HookReceiver                 │ │
│  │                   │  │                              │ │
│  │ - FSEvents on     │  │ - Unix Domain Socket server  │ │
│  │   ~/.claude/      │  │ - Receives events from hook  │ │
│  │   sessions/       │  │   scripts installed in       │ │
│  │ - Session         │  │   ~/.claude/settings.json    │ │
│  │   discovery &     │  │ - Events: Stop, Permission,  │ │
│  │   lifecycle       │  │   AskUserQuestion            │ │
│  │ - Process         │  │ - Rich context: tool name,   │ │
│  │   liveness check  │  │   transcript path, etc.      │ │
│  └──────────────────┘  └──────────────────────────────┘ │
└──────────────────────────────────────────────────────────┘
```

### 2.3 Data Flow

```
Claude Code Process
    │
    ├── [Stop event]              ──► Hook script ──► UDS ──► Claude Island App
    ├── [PermissionRequest event] ──► Hook script ──► UDS ──► Claude Island App
    └── [PreToolUse: AskUser]     ──► Hook script ──► UDS ──► Claude Island App
                                                                    │
                                                                    ▼
                                                         ┌──────────────────┐
                                                         │ Menu Bar / DI /  │
                                                         │ Notification     │
                                                         └──────────────────┘

~/.claude/sessions/{pid}.json  ──► FSEvents ──► Session lifecycle tracking
```

### 2.4 Why Not a VS Code Extension?

| Factor | VS Code Extension | macOS Native App |
|--------|-------------------|------------------|
| Terminal coverage | VS Code only | All terminals |
| System UI (menu bar, floating window) | Impossible from Electron sandbox | Full access |
| Development complexity | Two codebases (TS + Swift) | One codebase (Swift) |
| User experience | Split between VS Code settings and companion app | Unified native experience |
| Extensibility | Locked to VS Code ecosystem | Can monitor any CLI agent |

---

## 3. State Acquisition — How It Works

### 3.1 Channel 1: Claude Code Hooks (Primary — Rich Events)

On first launch, Claude Island auto-writes hook configuration into `~/.claude/settings.json`:

```json
{
  "hooks": {
    "Stop": [{
      "hooks": [{
        "type": "command",
        "command": "/Applications/Claude Island.app/Contents/Resources/hooks/on-stop.sh"
      }]
    }],
    "PermissionRequest": [{
      "hooks": [{
        "type": "command",
        "command": "/Applications/Claude Island.app/Contents/Resources/hooks/on-permission.sh"
      }]
    }],
    "PreToolUse": [{
      "matcher": "AskUserQuestion",
      "hooks": [{
        "type": "command",
        "command": "/Applications/Claude Island.app/Contents/Resources/hooks/on-question.sh"
      }]
    }]
  }
}
```

Each hook script:
1. Reads JSON from stdin (Claude Code provides structured event data)
2. Forwards the event to Claude Island App via Unix Domain Socket at `/tmp/claude-island.sock`
3. Exits immediately (hooks must be fast to avoid blocking Claude)

**Hook stdin data formats:**

Stop event:
```json
{
  "transcript_path": "/Users/x/.claude/projects/.../transcript.jsonl",
  "stop_hook_active": false,
  "session_id": "9444372a-..."
}
```

PermissionRequest event:
```json
{
  "tool_name": "Bash",
  "tool_input": { "command": "rm -rf dist/" },
  "session_id": "9444372a-..."
}
```

PreToolUse (AskUserQuestion) event:
```json
{
  "tool_name": "AskUserQuestion",
  "tool_input": { "question": "Should I proceed with the refactor?" },
  "session_id": "9444372a-..."
}
```

### 3.2 Channel 2: File Watching (Secondary — Session Lifecycle)

Claude Code writes session metadata to `~/.claude/sessions/{pid}.json`:

```json
{
  "pid": 60717,
  "sessionId": "9444372a-8130-4537-b4e0-e5586e2498f2",
  "cwd": "/Volumes/Extreme SSD/App Development/Claude island",
  "startedAt": 1775070988321,
  "kind": "interactive",
  "entrypoint": "claude-vscode"
}
```

**Detection flow:**
1. FSEvents monitors `~/.claude/sessions/` for file creation/deletion
2. On new file → parse JSON → register session in SessionManager
3. Periodically verify process liveness: `kill(pid, 0)` — if dead, mark as `done`
4. On file deletion → remove session from registry

### 3.3 How The Two Channels Complement Each Other

| Capability | FileWatcher | Hooks |
|-----------|------------|-------|
| Discover new sessions | Yes | No (hooks fire per-event, not on start) |
| Know working directory | Yes (from JSON) | No |
| Know entrypoint (vscode/cli) | Yes (from JSON) | No |
| Detect "needs permission" | No | Yes (PermissionRequest hook) |
| Detect "asking question" | No | Yes (PreToolUse hook) |
| Detect "task completed" | Indirectly (process exit) | Yes (Stop hook) |
| Get tool name / prompt content | No | Yes |
| Get transcript path | No | Yes (Stop hook) |

**Combined:** FileWatcher handles session discovery and lifecycle. Hooks handle rich real-time events.

---

## 4. UI Design

### 4.1 Menu Bar Icon

```
┌──────────────────────────────────────────┐
│  Status Bar                     🔵 3     │  ← Icon + active session count
└──────────────────────────────────────────┘
                                    │
                                    ▼
┌──────────────────────────────────────────┐
│  Claude Island                   Settings│
├──────────────────────────────────────────┤
│                                          │
│  ● Running    claude-island/             │  ← Green dot
│               Refactoring auth module    │
│               2 min ago                  │
│                                          │
│  ⏳ Waiting   my-api-project/            │  ← Yellow, pulsing
│               "Allow Bash: rm -rf dist/" │
│               [Approve] [Reject] [Jump]  │
│                                          │
│  ✓ Done       web-frontend/              │  ← Gray
│               Completed 5 min ago        │
│                                          │
├──────────────────────────────────────────┤
│  Quit Claude Island                      │
└──────────────────────────────────────────┘
```

### 4.2 Pseudo-Dynamic Island (Floating Window)

**Collapsed state** — small pill at top center of screen (near notch):
```
        ┌─────────────────────────┐
        │  🔵 3 agents running    │
        └─────────────────────────┘
```

**Expanded state** — when an agent needs approval:
```
        ┌──────────────────────────────────────┐
        │  ⏳ my-api-project/ needs approval   │
        │                                      │
        │  "Allow Bash: rm -rf dist/"          │
        │                                      │
        │  [Approve]  [Reject]  [Jump to Term] │
        └──────────────────────────────────────┘
```

**Window properties:**
- `NSWindow.Level.floating` (or `.statusBar`)
- `collectionBehavior: [.canJoinAllSpaces, .stationary, .ignoresCycle]`
- Transparent background, rounded corners via SwiftUI `clipShape(RoundedRectangle)`
- Spring animation for expand/collapse
- Auto-collapses after user action or 10s timeout

### 4.3 System Notifications

For when user is in a full-screen app:

```
┌─────────────────────────────────────────┐
│ Claude Island                      now  │
│                                         │
│ ⏳ Agent needs your approval            │
│ my-api-project/: "Allow Bash: rm -rf"  │
│                                         │
│     [Approve]         [Reject]          │
└─────────────────────────────────────────┘
```

Uses `UNUserNotificationCenter` with actionable notification categories.

### 4.4 Terminal Jump (Inspired by Vibe Island)

When user clicks "Jump to Term", the app activates the correct terminal window/tab:
- **VS Code:** Use `code --goto` or AppleScript to activate the window
- **iTerm2:** AppleScript `tell application "iTerm2" to activate`
- **Terminal.app:** AppleScript activation
- **Warp/Ghostty:** AppleScript or `open -a` activation

---

## 5. Data Model

```swift
// MARK: - Session State

enum SessionStatus: String, Codable {
    case running            // Agent is actively working
    case waitingPermission  // Agent needs tool permission (PermissionRequest hook)
    case waitingAnswer      // Agent asked user a question (PreToolUse AskUserQuestion)
    case stopped            // Agent stopped (Stop hook received)
    case done               // Process exited
}

struct AgentSession: Identifiable {
    let id: UUID = UUID()
    let sessionId: String           // Claude Code session ID
    let pid: Int                    // Process ID
    let cwd: String                 // Working directory
    let startedAt: Date
    let entrypoint: String          // "claude-vscode", "claude-cli", etc.
    
    var status: SessionStatus = .running
    var pendingPrompt: String?      // What tool/question needs approval
    var pendingToolName: String?    // e.g. "Bash", "Edit", "AskUserQuestion"
    var transcriptPath: String?     // Path to conversation transcript
    var updatedAt: Date = Date()
    
    var workspaceName: String {     // Last path component of cwd
        URL(fileURLWithPath: cwd).lastPathComponent
    }
    
    var isAlive: Bool {             // Check if process still exists
        kill(Int32(pid), 0) == 0
    }
}

// MARK: - Hook Events (received via Unix Domain Socket)

enum HookEvent: Codable {
    case stop(StopEvent)
    case permissionRequest(PermissionEvent)
    case askUserQuestion(QuestionEvent)
}

struct StopEvent: Codable {
    let sessionId: String
    let transcriptPath: String?
}

struct PermissionEvent: Codable {
    let sessionId: String
    let toolName: String
    let toolInput: [String: String]?
}

struct QuestionEvent: Codable {
    let sessionId: String
    let question: String
}
```

---

## 6. IPC Protocol

### Socket Path
```
/tmp/claude-island.sock
```

### Message Format (NDJSON)

Hook scripts → App:
```json
{"type":"stop","sessionId":"abc-123","transcriptPath":"/path/to/transcript.jsonl"}
{"type":"permission","sessionId":"abc-123","toolName":"Bash","toolInput":"rm -rf dist/"}
{"type":"question","sessionId":"abc-123","question":"Should I proceed with the refactor?"}
```

### Hook Script Template (bundled in app)

```bash
#!/bin/bash
# Read stdin (Claude provides JSON event data)
INPUT=$(cat)
# Forward to Claude Island app via Unix Domain Socket
echo "$INPUT" | nc -U /tmp/claude-island.sock 2>/dev/null
# Always exit 0 to not block Claude
exit 0
```

The actual hook scripts will be slightly more sophisticated — they'll inject `sessionId` from environment variables and format the message properly. But the core idea is: **read stdin, forward to socket, exit fast.**

---

## 7. Auto-Setup (Zero-Config)

On first launch, Claude Island:

1. Reads `~/.claude/settings.json`
2. Merges its hook entries into the existing `hooks` configuration (preserving user's other hooks)
3. Writes the bundled hook scripts to `~/Library/Application Support/ClaudeIsland/hooks/`
4. Verifies the socket server is running

On app uninstall / cleanup:
- Provides a menu option to remove hooks from `settings.json`

**Important:** Must handle the case where user already has hooks configured (like the Claude Notifier scripts currently installed). Our hooks should coexist, not replace.

---

## 8. Development Phases

### Phase 1 — Foundation (Week 1-2)
- [ ] Set up Xcode project (macOS menu bar app, SwiftUI lifecycle)
- [ ] Implement Unix Domain Socket server
- [ ] Implement FSEvents file watcher for `~/.claude/sessions/`
- [ ] Parse session JSON files, register/remove sessions
- [ ] Implement process liveness checking
- [ ] Write hook scripts (bash, reads stdin → forwards to UDS)
- [ ] Auto-setup: merge hooks into `~/.claude/settings.json`
- [ ] Basic menu bar icon with active session count
- [ ] Simple popover listing all sessions

### Phase 2 — Rich Events & Notifications (Week 3-4)
- [ ] Handle PermissionRequest events (show tool name + input)
- [ ] Handle AskUserQuestion events (show question text)
- [ ] Handle Stop events (mark session as stopped)
- [ ] System notifications with action buttons (Approve/Reject)
- [ ] Sound alerts (configurable)
- [ ] Session detail view in popover

### Phase 3 — Dynamic Island UI (Week 5-6)
- [ ] Floating window positioned near notch
- [ ] Collapsed state (pill showing agent count)
- [ ] Expanded state (approval prompt with buttons)
- [ ] Spring animations for state transitions
- [ ] Auto-collapse on action or timeout
- [ ] Window level and collection behavior for all-spaces visibility

### Phase 4 — Terminal Jump & Polish (Week 7-8)
- [ ] Terminal detection (which app is running the Claude process)
- [ ] AppleScript-based terminal activation (iTerm2, Terminal.app, VS Code)
- [ ] Settings panel (launch at login, notification prefs, sounds, theme)
- [ ] Coexistence with other hooks (Claude Notifier, Vibe Island, etc.)
- [ ] App icon and branding
- [ ] Code signing and notarization
- [ ] `.dmg` installer
- [ ] Stress test with 10+ concurrent sessions
- [ ] Error recovery (socket reconnection, crash resilience)

---

## 9. Technical Risks & Mitigations

| Risk | Severity | Mitigation |
|------|----------|------------|
| Hook stdin data format changes in future Claude Code versions | 🟡 Medium | Defensive JSON parsing; hooks API is more stable than terminal output |
| `~/.claude/sessions/` file format changes | 🟡 Medium | Keep parser modular; this is supplementary to hooks |
| Conflicts with existing hooks (Claude Notifier, Vibe Island) | 🟡 Medium | Merge hooks (append, don't replace); support multiple hook entries per event |
| macOS permission dialogs (Notifications) | 🟡 Medium | Clear onboarding flow |
| Floating window hidden in full-screen apps | 🟡 Medium | `canJoinAllSpaces` + `stationary`; fallback to system notification |
| PID reuse by OS | 🟢 Low | Cross-check PID + startedAt; verify process name |
| App signing & Gatekeeper | 🟡 Medium | Apple Developer account; notarize builds |
| Hook script execution speed | 🟢 Low | Scripts just forward to socket and exit; <10ms |

---

## 10. Differentiation from Vibe Island

| Feature | Vibe Island | Claude Island (planned) |
|---------|------------|----------------------|
| Price | $19.99 | TBD (could be open-source or freemium) |
| Multi-agent | 6 agents | Start with Claude Code, expand later |
| Terminal jump | 13+ terminals | Core terminals first (VS Code, iTerm2, Terminal.app) |
| GUI approval | Yes | Yes — with richer context display |
| Plan preview | Markdown render | Phase 2+ feature |
| Dynamic Island UI | Yes | Yes — with customizable position/style |
| Open source | No | TBD |
| Hook coexistence | Replaces existing hooks? | Merges with existing hooks |

---

## 11. Future Roadmap

- **v1.1** — Multi-agent: Gemini CLI, Codex CLI support
- **v1.2** — Cursor Agent, OpenCode support
- **v1.3** — Plan preview with Markdown rendering
- **v2.0** — Session history, analytics, cost tracking
- **v2.1** — iOS companion app (real Dynamic Island via ActivityKit)
- **v3.0** — "Universal AI Agent Control Center"
