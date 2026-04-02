import Foundation

// MARK: - Session Status

enum SessionStatus: String, Codable, CaseIterable {
    case running
    case waitingPermission
    case waitingAnswer
    case stopped
    case done

    var displayName: String {
        switch self {
        case .running: "Running"
        case .waitingPermission: "Needs Permission"
        case .waitingAnswer: "Needs Answer"
        case .stopped: "Stopped"
        case .done: "Done"
        }
    }

    var iconName: String {
        switch self {
        case .running: "circle.fill"
        case .waitingPermission: "exclamationmark.circle.fill"
        case .waitingAnswer: "questionmark.circle.fill"
        case .stopped: "stop.circle.fill"
        case .done: "checkmark.circle.fill"
        }
    }

    var isActive: Bool {
        switch self {
        case .running, .waitingPermission, .waitingAnswer: true
        case .stopped, .done: false
        }
    }

    var needsAttention: Bool {
        self == .waitingPermission || self == .waitingAnswer
    }
}

// MARK: - Agent Session

struct AgentSession: Identifiable, Equatable {
    let id: UUID
    let sessionId: String
    let pid: Int
    let cwd: String
    let startedAt: Date
    let entrypoint: String

    var status: SessionStatus
    var title: String?
    var pendingPrompt: String?
    var pendingToolName: String?
    var transcriptPath: String?
    var updatedAt: Date
    var hasUnreadCompletion: Bool = false

    var workspaceName: String {
        URL(fileURLWithPath: cwd).lastPathComponent
    }

    /// Display title: user's first prompt, falling back to workspace name
    var displayTitle: String {
        title ?? workspaceName
    }

    var isAlive: Bool {
        kill(Int32(pid), 0) == 0
    }

    var timeAgo: String {
        let interval = Date().timeIntervalSince(updatedAt)
        if interval < 60 { return "just now" }
        if interval < 3600 { return "\(Int(interval / 60))m ago" }
        if interval < 86400 { return "\(Int(interval / 3600))h ago" }
        return "\(Int(interval / 86400))d ago"
    }

    var duration: String {
        let end = status.isActive ? Date() : updatedAt
        let interval = end.timeIntervalSince(startedAt)
        if interval < 60 { return "\(Int(interval))s" }
        if interval < 3600 {
            let m = Int(interval / 60)
            let s = Int(interval) % 60
            return "\(m)m \(s)s"
        }
        let h = Int(interval / 3600)
        let m = Int(interval / 60) % 60
        return "\(h)h \(m)m"
    }

    init(
        sessionId: String,
        pid: Int,
        cwd: String,
        startedAt: Date,
        entrypoint: String
    ) {
        self.id = UUID()
        self.sessionId = sessionId
        self.pid = pid
        self.cwd = cwd
        self.startedAt = startedAt
        self.entrypoint = entrypoint
        self.status = .running
        self.updatedAt = Date()
    }
}

// MARK: - Session File (from ~/.claude/sessions/{pid}.json)

struct SessionFile: Codable {
    let pid: Int
    let sessionId: String
    let cwd: String
    let startedAt: Int64 // milliseconds
    let kind: String
    let entrypoint: String

    var startDate: Date {
        Date(timeIntervalSince1970: TimeInterval(startedAt) / 1000.0)
    }
}
