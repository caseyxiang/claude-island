import Foundation

// MARK: - Session Status

enum SessionStatus: String, Codable, CaseIterable {
    case working          // Claude is actively processing
    case idle             // Claude finished, waiting for user input
    case waitingPermission // Claude needs tool permission
    case waitingAnswer    // Claude asked user a question
    case done             // Process exited

    var displayName: String {
        switch self {
        case .working: "Working"
        case .idle: "Idle"
        case .waitingPermission: "Needs Permission"
        case .waitingAnswer: "Needs Answer"
        case .done: "Done"
        }
    }

    var iconName: String {
        switch self {
        case .working: "gearshape.fill"
        case .idle: "moon.zzz.fill"
        case .waitingPermission: "exclamationmark.bubble.fill"
        case .waitingAnswer: "questionmark.bubble.fill"
        case .done: "checkmark.circle.fill"
        }
    }

    var isActive: Bool {
        switch self {
        case .working, .idle, .waitingPermission, .waitingAnswer: true
        case .done: false
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
    var lastUserPrompt: String?
    var lastAssistantMessage: String?
    var liveResponse: String?  // streaming response while working

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
        self.status = .idle
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
