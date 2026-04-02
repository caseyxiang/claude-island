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

    /// Sessions sorted by priority: needsAttention > working > completed > idle
    var sortedSessions: [AgentSession] {
        sessions.sorted { a, b in
            sortOrder(a) < sortOrder(b)
        }
    }

    private func sortOrder(_ session: AgentSession) -> Int {
        if session.status.needsAttention { return 0 }
        if session.status == .working { return 1 }
        if session.hasUnreadCompletion { return 2 }
        if session.status == .idle { return 3 }
        return 4 // done
    }

    // MARK: - Collectors

    let fileWatcher = FileWatcher()
    let hookReceiver = HookReceiver()
    let processMonitor = ProcessMonitor()
    let transcriptWatcher = TranscriptWatcher()

    // MARK: - Event callbacks for UI

    var onAttentionNeeded: ((AgentSession) -> Void)?
    var onSessionCompleted: ((AgentSession) -> Void)?

    // MARK: - Lifecycle

    func start() {
        setupFileWatcher()
        setupHookReceiver()
        setupProcessMonitor()
        setupTranscriptWatcher()
    }

    func stop() {
        fileWatcher.stop()
        hookReceiver.stop()
        transcriptWatcher.stop()
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
        startTranscriptWatch(for: session)
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
        hookReceiver.onEvent = { [weak self] message in
            self?.handleHookEvent(message)
        }
        do {
            try hookReceiver.start()
        } catch {
            logger.error("Failed to start hook receiver: \(error.localizedDescription)")
        }
    }

    private func handleHookEvent(_ message: HookMessage) {
        print("[HOOK] Received: type=\(message.type.rawValue) sessionId=\(message.sessionId ?? "nil") status=\(message.hookStatus ?? "nil")")
        print("[HOOK] Known sessions: \(sessions.map { "\($0.sessionId.prefix(8))=\($0.status.rawValue)" }.joined(separator: ", "))")

        if let idx = findSessionIndex(for: message) {
            print("[HOOK] Matched session index=\(idx): \(sessions[idx].displayTitle)")
        } else {
            print("[HOOK] NO MATCH for sessionId=\(message.sessionId ?? "nil")")
        }

        // If any hook event has status field, use it to infer working/idle
        if let index = findSessionIndex(for: message),
           message.type != .stop && message.type != .userPrompt {
            let isWaiting = message.hookStatus == "waiting_for_input"
            if !isWaiting && sessions[index].status == .idle {
                sessions[index].status = .working
                sessions[index].hasUnreadCompletion = false
                sessions[index].updatedAt = Date()
            }
        }

        switch message.type {
        case .stop:
            // Claude finished responding — transition to idle
            let session: AgentSession
            if let index = findSessionIndex(for: message) {
                sessions[index].status = .idle
                sessions[index].pendingPrompt = nil
                sessions[index].pendingToolName = nil
                sessions[index].transcriptPath = message.transcriptPath
                sessions[index].updatedAt = Date()
                sessions[index].hasUnreadCompletion = true
                transcriptWatcher.stopWatching(sessionId: sessions[index].sessionId)
                // Only update prompt if we got one (Stop hook usually doesn't have it)
                if let prompt = message.lastPrompt, !prompt.isEmpty {
                    sessions[index].lastUserPrompt = prompt
                }
                // Update response from Stop hook; fall back to liveResponse if not provided
                if let response = message.lastResponse, !response.isEmpty {
                    sessions[index].lastAssistantMessage = response
                } else if let live = sessions[index].liveResponse, !live.isEmpty {
                    sessions[index].lastAssistantMessage = live
                }
                sessions[index].liveResponse = nil
                print("[HOOK] stop: prompt=\(sessions[index].lastUserPrompt ?? "nil") response=\(sessions[index].lastAssistantMessage?.prefix(50) ?? "nil")")
                session = sessions[index]
            } else {
                session = AgentSession(
                    sessionId: message.sessionId ?? UUID().uuidString,
                    pid: message.pid ?? 0,
                    cwd: message.cwd ?? "Unknown",
                    startedAt: Date(),
                    entrypoint: "claude"
                )
            }
            logger.info("Session idle: \(session.workspaceName)")
            onSessionCompleted?(session)

        case .userPrompt:
            // User submitted a new prompt — transition to working
            guard let index = findSessionIndex(for: message) else { return }
            sessions[index].status = .working
            sessions[index].pendingPrompt = nil
            sessions[index].pendingToolName = nil
            sessions[index].hasUnreadCompletion = false
            sessions[index].lastAssistantMessage = nil
            sessions[index].liveResponse = nil
            sessions[index].updatedAt = Date()
            if let prompt = message.lastPrompt, !prompt.isEmpty {
                sessions[index].lastUserPrompt = prompt
            }
            // Start watching transcript for live response (read recent to pick up replies)
            startTranscriptWatch(for: sessions[index], readRecent: true)
            logger.info("Session working: \(self.sessions[index].workspaceName)")

        case .permission:
            guard let index = findSessionIndex(for: message) else {
                logger.warning("Permission event for unknown session: \(message.sessionId ?? "nil")")
                return
            }
            // Any non-stop event means Claude is working
            if sessions[index].status == .idle {
                sessions[index].hasUnreadCompletion = false
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
        // Notify completion if not already idle
        if session.status != .idle {
            onSessionCompleted?(session)
        }
        sessions.remove(at: index)
    }

    // MARK: - Transcript Watcher

    private func setupTranscriptWatcher() {
        transcriptWatcher.onResponseUpdate = { [weak self] sessionId, response, prompt in
            guard let self,
                  let index = sessions.firstIndex(where: { $0.sessionId == sessionId }) else { return }
            // Only update text, don't change status here
            if sessions[index].status == .working {
                sessions[index].liveResponse = response
            }
            if let prompt, !prompt.isEmpty {
                sessions[index].lastUserPrompt = prompt
            }
        }
        // Detect working based on transcript file growth (idle → working only)
        // Completion (working → idle) is handled by Stop hook
        transcriptWatcher.onActivityChange = { [weak self] sessionId, isGrowing in
            guard let self,
                  let index = sessions.firstIndex(where: { $0.sessionId == sessionId }) else { return }
            if isGrowing && sessions[index].status == .idle {
                sessions[index].status = .working
                sessions[index].hasUnreadCompletion = false
                sessions[index].updatedAt = Date()
            }
        }

        transcriptWatcher.start()

        // Start watching all existing sessions
        for session in sessions {
            startTranscriptWatch(for: session)
        }
    }

    private func startTranscriptWatch(for session: AgentSession, readRecent: Bool = false) {
        // Find transcript path
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let encoded = session.cwd.map { ch -> Character in
            if ch.isLetter || ch.isNumber || ch == "-" { return ch }
            return "-"
        }
        let encodedCwd = String(encoded)
        let path = "\(home)/.claude/projects/\(encodedCwd)/\(session.sessionId).jsonl"

        if FileManager.default.fileExists(atPath: path) {
            transcriptWatcher.startWatching(sessionId: session.sessionId, transcriptPath: path, readRecent: readRecent)
        } else {
            // Scan project dirs
            let projectsDir = "\(home)/.claude/projects"
            if let dirs = try? FileManager.default.contentsOfDirectory(atPath: projectsDir) {
                for dir in dirs {
                    let candidate = "\(projectsDir)/\(dir)/\(session.sessionId).jsonl"
                    if FileManager.default.fileExists(atPath: candidate) {
                        transcriptWatcher.startWatching(sessionId: session.sessionId, transcriptPath: candidate, readRecent: readRecent)
                        break
                    }
                }
            }
        }
    }

    // MARK: - Manual Actions

    func dismissSession(_ session: AgentSession) {
        sessions.removeAll { $0.id == session.id }
    }

    func approvePermission(session: AgentSession, approved: Bool) {
        hookReceiver.sendApprovalDecision(sessionId: session.sessionId, approved: approved)
        // Update session state — back to working
        if let index = sessions.firstIndex(where: { $0.id == session.id }) {
            sessions[index].status = .working
            sessions[index].pendingPrompt = nil
            sessions[index].pendingToolName = nil
            sessions[index].updatedAt = Date()
        }
    }

    func markAsRead(_ session: AgentSession) {
        guard let index = sessions.firstIndex(where: { $0.id == session.id }) else { return }
        sessions[index].hasUnreadCompletion = false
    }

    // MARK: - Title Extraction

    /// Reads the transcript file to extract the AI-generated title (or first user prompt as fallback).
    private static func loadTitle(for file: SessionFile) -> String? {
        guard let transcriptPath = findTranscriptPath(for: file) else { return nil }

        // First: scan the ENTIRE file for custom-title (user-edited, highest priority)
        // custom-title can appear anywhere in the file
        if let customTitle = scanForCustomTitle(path: transcriptPath) {
            return truncateTitle(customTitle)
        }

        guard let handle = FileHandle(forReadingAtPath: transcriptPath) else { return nil }
        defer { handle.closeFile() }

        // Read first 256KB for ai-title and first user message
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

            // AI-generated title
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

    /// Scan entire transcript file for the LAST custom-title entry (user-edited title).
    private static func scanForCustomTitle(path: String) -> String? {
        guard let data = FileManager.default.contents(atPath: path),
              let text = String(data: data, encoding: .utf8) else { return nil }

        var lastCustomTitle: String?
        // Scan from end — custom-title could be appended later when user edits
        for line in text.components(separatedBy: .newlines).reversed() {
            if line.contains("\"custom-title\"") {
                if let lineData = line.trimmingCharacters(in: .whitespaces).data(using: .utf8),
                   let json = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any],
                   (json["type"] as? String) == "custom-title",
                   let title = json["customTitle"] as? String, !title.isEmpty {
                    lastCustomTitle = title
                    break
                }
            }
        }
        return lastCustomTitle
    }

    /// Read the last user prompt and assistant response from a transcript file.
    private static func readLastConversation(path: String) -> (prompt: String?, response: String?) {
        guard let handle = FileHandle(forReadingAtPath: path) else { return (nil, nil) }
        defer { handle.closeFile() }

        handle.seekToEndOfFile()
        let size = handle.offsetInFile
        let readFrom: UInt64 = size > 32768 ? size - 32768 : 0
        handle.seek(toFileOffset: readFrom)
        let data = handle.readDataToEndOfFile()
        guard let text = String(data: data, encoding: .utf8) else { return (nil, nil) }

        var prompt: String?
        var response: String?

        for line in text.components(separatedBy: .newlines).reversed() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty,
                  let lineData = trimmed.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any] else { continue }

            let type = json["type"] as? String

            if type == "assistant" && response == nil,
               let msg = json["message"] as? [String: Any],
               let content = msg["content"] as? [[String: Any]] {
                for block in content {
                    if (block["type"] as? String) == "text", let t = block["text"] as? String {
                        response = String(t.prefix(300))
                        break
                    }
                }
            }

            if type == "user" && prompt == nil,
               let msg = json["message"] as? [String: Any],
               let content = msg["content"] as? [[String: Any]] {
                for block in content {
                    if (block["type"] as? String) == "text", let rawText = block["text"] as? String {
                        var cleaned = rawText
                            .replacingOccurrences(of: "<[^>]+>[\\s\\S]*?</[^>]+>", with: "", options: .regularExpression)
                            .replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
                            .trimmingCharacters(in: .whitespacesAndNewlines)
                        if !cleaned.isEmpty {
                            prompt = String(cleaned.components(separatedBy: .newlines).first!.prefix(150))
                            break
                        }
                    }
                }
            }

            if prompt != nil && response != nil { break }
        }
        return (prompt, response)
    }

    private static func truncateTitle(_ text: String) -> String {
        if text.count > 60 {
            return String(text.prefix(57)) + "..."
        }
        return text
    }
}
