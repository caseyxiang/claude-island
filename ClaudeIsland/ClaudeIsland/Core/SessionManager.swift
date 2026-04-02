import Foundation
import OSLog

/// Central session registry. Manages all known Claude Code sessions,
/// receives events from FileWatcher and HookReceiver, and publishes
/// state changes for the UI.
@Observable
final class SessionManager {
    private let logger = Logger(subsystem: "com.claudeisland", category: "SessionManager")

    // MARK: - Published State

    private(set) var sessions: [AgentSession] = []

    var activeSessions: [AgentSession] {
        sessions.filter { $0.status.isActive }
    }

    var attentionSessions: [AgentSession] {
        sessions.filter { $0.status.needsAttention }
    }

    var activeCount: Int {
        activeSessions.count
    }

    // MARK: - Collectors

    let fileWatcher = FileWatcher()
    let hookReceiver = HookReceiver()
    let processMonitor = ProcessMonitor()

    // MARK: - Event callbacks for UI

    var onAttentionNeeded: ((AgentSession) -> Void)?
    var onSessionCompleted: ((AgentSession) -> Void)?

    // MARK: - Lifecycle

    func start() {
        setupFileWatcher()
        setupHookReceiver()
        setupProcessMonitor()
    }

    func stop() {
        fileWatcher.stop()
        Task { await hookReceiver.stop() }
        processMonitor.stop()
    }

    // MARK: - File Watcher

    private func setupFileWatcher() {
        fileWatcher.onSessionDiscovered = { [weak self] sessionFile in
            self?.handleSessionDiscovered(sessionFile)
        }
        fileWatcher.onSessionRemoved = { [weak self] sessionId in
            self?.handleSessionRemoved(sessionId)
        }
        fileWatcher.start()
    }

    private func handleSessionDiscovered(_ file: SessionFile) {
        // Don't add duplicates
        guard !sessions.contains(where: { $0.sessionId == file.sessionId }) else { return }

        // Skip dead processes entirely
        guard kill(Int32(file.pid), 0) == 0 else {
            logger.info("Skipping dead session: pid=\(file.pid)")
            return
        }

        var session = AgentSession(
            sessionId: file.sessionId,
            pid: file.pid,
            cwd: file.cwd,
            startedAt: file.startDate,
            entrypoint: file.entrypoint
        )

        // Load title from transcript
        session.title = Self.loadTitle(for: file)

        sessions.append(session)
        processMonitor.addPid(file.pid)
        logger.info("Session added: \(session.displayTitle) (pid=\(session.pid))")
    }

    private func handleSessionRemoved(_ sessionId: String) {
        guard let index = sessions.firstIndex(where: { $0.sessionId == sessionId }) else { return }
        let session = sessions[index]
        processMonitor.removePid(session.pid)
        sessions.remove(at: index)
        logger.info("Session removed: \(session.workspaceName)")
    }

    // MARK: - Hook Receiver

    private func setupHookReceiver() {
        Task {
            await hookReceiver.setOnEvent { [weak self] message in
                Task { @MainActor in
                    self?.handleHookEvent(message)
                }
            }
            do {
                try await hookReceiver.start()
            } catch {
                logger.error("Failed to start hook receiver: \(error.localizedDescription)")
            }
        }
    }

    private func handleHookEvent(_ message: HookMessage) {
        switch message.type {
        case .stop:
            // Task completed — always send notification, even if session already removed
            let session: AgentSession
            if let index = findSessionIndex(for: message) {
                sessions[index].pendingPrompt = nil
                sessions[index].pendingToolName = nil
                sessions[index].transcriptPath = message.transcriptPath
                sessions[index].updatedAt = Date()
                sessions[index].hasUnreadCompletion = true
                session = sessions[index]
                sessions[index].status = .running
            } else {
                // Session already removed (process exited before hook arrived)
                // Build a temporary session for the notification
                session = AgentSession(
                    sessionId: message.sessionId ?? UUID().uuidString,
                    pid: message.pid ?? 0,
                    cwd: message.cwd ?? "Unknown",
                    startedAt: Date(),
                    entrypoint: "claude"
                )
            }
            logger.info("Task completed: \(session.workspaceName)")
            onSessionCompleted?(session)

        case .permission:
            guard let index = findSessionIndex(for: message) else {
                logger.warning("Permission event for unknown session: \(message.sessionId ?? "nil")")
                return
            }
            sessions[index].status = .waitingPermission
            sessions[index].pendingToolName = message.toolName
            sessions[index].pendingPrompt = formatPermissionPrompt(message)
            sessions[index].updatedAt = Date()
            logger.info("Session needs permission: \(self.sessions[index].workspaceName) — \(message.toolName ?? "")")
            onAttentionNeeded?(sessions[index])

        case .question:
            guard let index = findSessionIndex(for: message) else {
                logger.warning("Question event for unknown session: \(message.sessionId ?? "nil")")
                return
            }
            sessions[index].status = .waitingAnswer
            sessions[index].pendingToolName = "AskUserQuestion"
            sessions[index].pendingPrompt = message.question ?? "Claude is asking a question"
            sessions[index].updatedAt = Date()
            logger.info("Session asks question: \(self.sessions[index].workspaceName)")
            onAttentionNeeded?(sessions[index])
        }
    }

    private func findSessionIndex(for message: HookMessage) -> Int? {
        // Try by sessionId first
        if let sessionId = message.sessionId,
           let index = sessions.firstIndex(where: { $0.sessionId == sessionId }) {
            return index
        }
        // Fallback to pid
        if let pid = message.pid,
           let index = sessions.firstIndex(where: { $0.pid == pid }) {
            return index
        }
        return nil
    }

    private func formatPermissionPrompt(_ message: HookMessage) -> String {
        let tool = message.toolName ?? "Unknown tool"
        if let input = message.toolInput {
            return "\(tool): \(input)"
        }
        return "Allow \(tool)?"
    }

    // MARK: - Process Monitor

    private func setupProcessMonitor() {
        processMonitor.onProcessDied = { [weak self] pid in
            Task { @MainActor in
                self?.handleProcessDied(pid)
            }
        }
        processMonitor.start()
    }

    private func handleProcessDied(_ pid: Int) {
        guard let index = sessions.firstIndex(where: { $0.pid == pid }) else { return }
        let session = sessions[index]
        logger.info("Session process died: \(session.workspaceName) (pid=\(pid))")
        // Notify completion if Stop hook hasn't already fired
        if session.status != .stopped {
            onSessionCompleted?(session)
        }
        sessions.remove(at: index)
    }

    // MARK: - Manual Actions

    func dismissSession(_ session: AgentSession) {
        sessions.removeAll { $0.id == session.id }
    }

    func markAsRead(_ session: AgentSession) {
        guard let index = sessions.firstIndex(where: { $0.id == session.id }) else { return }
        sessions[index].hasUnreadCompletion = false
    }

    // MARK: - Title Extraction

    /// Reads the transcript file to extract the AI-generated title (or first user prompt as fallback).
    private static func loadTitle(for file: SessionFile) -> String? {
        guard let transcriptPath = findTranscriptPath(for: file) else { return nil }

        guard let handle = FileHandle(forReadingAtPath: transcriptPath) else { return nil }
        defer { handle.closeFile() }

        // Read first 256KB — ai-title is in the first few lines, but user messages
        // may be preceded by large system prompts
        let data = handle.readData(ofLength: 256 * 1024)
        guard let text = String(data: data, encoding: .utf8) else { return nil }

        var firstUserPrompt: String?

        for line in text.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty,
                  let lineData = trimmed.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any] else {
                continue
            }

            let type = json["type"] as? String

            // Best: AI-generated title
            if type == "ai-title", let aiTitle = json["aiTitle"] as? String, !aiTitle.isEmpty {
                return truncateTitle(aiTitle)
            }

            // Fallback: first user message
            if type == "user" && firstUserPrompt == nil,
               let message = json["message"] as? [String: Any],
               let content = message["content"] as? [[String: Any]] {
                for block in content {
                    guard (block["type"] as? String) == "text",
                          let rawText = block["text"] as? String else { continue }

                    let cleaned = rawText
                        .replacingOccurrences(of: "<system-reminder>[\\s\\S]*?</system-reminder>", with: "", options: .regularExpression)
                        .replacingOccurrences(of: "<ide_[^>]+>[\\s\\S]*?</ide_[^>]+>", with: "", options: .regularExpression)
                        .replacingOccurrences(of: "<task-notification>[\\s\\S]*?</task-notification>", with: "", options: .regularExpression)
                        .replacingOccurrences(of: "<ide_selection>[\\s\\S]*?</ide_selection>", with: "", options: .regularExpression)
                        .replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
                        .trimmingCharacters(in: .whitespacesAndNewlines)

                    if !cleaned.isEmpty {
                        let firstLine = cleaned.components(separatedBy: .newlines).first ?? cleaned
                        firstUserPrompt = truncateTitle(firstLine)
                        break
                    }
                }
            }
        }

        return firstUserPrompt
    }

    /// Finds the transcript .jsonl file for a session.
    private static func findTranscriptPath(for file: SessionFile) -> String? {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let projectsDir = "\(home)/.claude/projects"

        // Encode cwd: replace non-alphanumeric (except -) with -
        let encoded = file.cwd.map { ch -> Character in
            if ch.isLetter || ch.isNumber || ch == "-" { return ch }
            return "-"
        }
        let encodedCwd = String(encoded)

        let path = "\(projectsDir)/\(encodedCwd)/\(file.sessionId).jsonl"
        if FileManager.default.fileExists(atPath: path) {
            return path
        }

        // Fallback: scan project directories for matching sessionId
        let fm = FileManager.default
        guard let dirs = try? fm.contentsOfDirectory(atPath: projectsDir) else { return nil }
        for dir in dirs {
            let candidate = "\(projectsDir)/\(dir)/\(file.sessionId).jsonl"
            if fm.fileExists(atPath: candidate) {
                return candidate
            }
        }
        return nil
    }

    private static func truncateTitle(_ text: String) -> String {
        if text.count > 60 {
            return String(text.prefix(57)) + "..."
        }
        return text
    }
}

// MARK: - Actor extension for setting callback

extension HookReceiver {
    func setOnEvent(_ handler: @escaping (HookMessage) -> Void) {
        self.onEvent = handler
    }
}
