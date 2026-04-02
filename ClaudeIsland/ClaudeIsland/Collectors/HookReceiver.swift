import Foundation
import OSLog

/// Listens on a Unix Domain Socket for hook events from Claude Code hook scripts.
/// For permission requests, keeps the connection open to send back approval decisions.
final class HookReceiver {
    static let socketPath = "/tmp/claude-island.sock"

    private let logger = Logger(subsystem: "com.claudeisland", category: "HookReceiver")
    private var listenSocket: Int32 = -1
    private var isRunning = false
    private let queue = DispatchQueue(label: "com.claudeisland.hookreceiver", attributes: .concurrent)

    /// Callback for received hook events (called on main queue)
    var onEvent: ((HookMessage) -> Void)?

    /// Pending permission requests waiting for user decision.
    /// Key: sessionId, Value: client socket fd
    private var pendingApprovals: [String: Int32] = [:]
    private let approvalLock = NSLock()

    func start() throws {
        guard !isRunning else { return }

        unlink(Self.socketPath)

        listenSocket = socket(AF_UNIX, SOCK_STREAM, 0)
        guard listenSocket >= 0 else {
            throw HookReceiverError.socketCreationFailed(errno)
        }

        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        let pathBytes = Self.socketPath.utf8CString
        let sunPathSize = MemoryLayout.size(ofValue: addr.sun_path)
        withUnsafeMutableBytes(of: &addr.sun_path) { rawBuf in
            let buf = rawBuf.assumingMemoryBound(to: CChar.self)
            for (i, byte) in pathBytes.enumerated() where i < sunPathSize {
                buf[i] = byte
            }
        }

        let bindResult = withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockPtr in
                bind(listenSocket, sockPtr, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard bindResult == 0 else {
            close(listenSocket)
            throw HookReceiverError.bindFailed(errno)
        }

        chmod(Self.socketPath, 0o666)

        guard listen(listenSocket, 10) == 0 else {
            close(listenSocket)
            throw HookReceiverError.listenFailed(errno)
        }

        isRunning = true
        logger.info("Hook receiver listening on \(Self.socketPath)")

        let sock = listenSocket
        queue.async { [weak self] in
            self?.acceptLoop(socket: sock)
        }
    }

    func stop() {
        guard isRunning else { return }
        isRunning = false
        if listenSocket >= 0 {
            close(listenSocket)
            listenSocket = -1
        }
        // Close any pending approval sockets
        approvalLock.lock()
        for (_, fd) in pendingApprovals {
            close(fd)
        }
        pendingApprovals.removeAll()
        approvalLock.unlock()
        unlink(Self.socketPath)
        logger.info("Hook receiver stopped")
    }

    // MARK: - Approval Response

    /// Send approval decision back to a waiting hook script.
    func sendApprovalDecision(sessionId: String, approved: Bool) {
        approvalLock.lock()
        guard let clientSocket = pendingApprovals.removeValue(forKey: sessionId) else {
            approvalLock.unlock()
            logger.warning("No pending approval for session \(sessionId)")
            return
        }
        approvalLock.unlock()

        let decision = approved ? "approve" : "block"
        let response = "{\"decision\":\"\(decision)\"}\n"

        queue.async { [weak self] in
            if let data = response.data(using: .utf8) {
                data.withUnsafeBytes { ptr in
                    _ = write(clientSocket, ptr.baseAddress!, data.count)
                }
            }
            close(clientSocket)
            self?.logger.info("Sent approval decision: \(decision) for session \(sessionId)")
        }
    }

    // MARK: - Accept Loop

    private func acceptLoop(socket listenSock: Int32) {
        while isRunning {
            var clientAddr = sockaddr_un()
            var clientAddrLen = socklen_t(MemoryLayout<sockaddr_un>.size)

            let clientSocket = withUnsafeMutablePointer(to: &clientAddr) { ptr in
                ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockPtr in
                    accept(listenSock, sockPtr, &clientAddrLen)
                }
            }

            if clientSocket < 0 {
                if !isRunning { break }
                continue
            }

            queue.async { [weak self] in
                self?.handleClient(socket: clientSocket)
            }
        }
    }

    private func handleClient(socket clientSocket: Int32) {
        // Set read timeout
        var timeout = timeval(tv_sec: 5, tv_usec: 0)
        setsockopt(clientSocket, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))

        var data = Data()
        let bufferSize = 4096
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
        defer { buffer.deallocate() }

        while true {
            let bytesRead = read(clientSocket, buffer, bufferSize)
            if bytesRead <= 0 { break }
            data.append(buffer, count: bytesRead)
            // If we got a newline, we have a complete message
            if data.contains(UInt8(ascii: "\n")) { break }
        }

        guard !data.isEmpty else {
            close(clientSocket)
            return
        }

        let text = String(data: data, encoding: .utf8) ?? ""
        for line in text.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { continue }
            guard let lineData = trimmed.data(using: .utf8) else { continue }

            do {
                let message = try JSONDecoder().decode(HookMessage.self, from: lineData)
                logger.info("Received hook event: \(message.type.rawValue) for session \(message.sessionId ?? "unknown")")

                // Check if this is a blocking permission request
                if message.type == .permission, message.waitingApproval == true,
                   let sessionId = message.sessionId {
                    // Keep the socket open for sending back the decision
                    approvalLock.lock()
                    pendingApprovals[sessionId] = clientSocket
                    approvalLock.unlock()
                    logger.info("Holding connection for approval: session \(sessionId)")

                    DispatchQueue.main.async { [weak self] in
                        self?.onEvent?(message)
                    }
                    // Don't close the socket — it stays open until we send a decision
                    return
                }

                DispatchQueue.main.async { [weak self] in
                    self?.onEvent?(message)
                }
            } catch {
                logger.error("Failed to parse hook message: \(error.localizedDescription) — raw: \(trimmed)")
            }
        }

        // Close socket for non-blocking events
        close(clientSocket)
    }
}

enum HookReceiverError: Error, LocalizedError {
    case socketCreationFailed(Int32)
    case bindFailed(Int32)
    case listenFailed(Int32)

    var errorDescription: String? {
        switch self {
        case .socketCreationFailed(let e): "Failed to create socket: \(e)"
        case .bindFailed(let e): "Failed to bind socket: \(e)"
        case .listenFailed(let e): "Failed to listen on socket: \(e)"
        }
    }
}
