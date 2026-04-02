import Foundation
import OSLog

/// Listens on a Unix Domain Socket for hook events from Claude Code hook scripts.
/// Hook scripts forward structured JSON events to this socket.
actor HookReceiver {
    static let socketPath = "/tmp/claude-island.sock"

    private let logger = Logger(subsystem: "com.claudeisland", category: "HookReceiver")
    private var listenSocket: Int32 = -1
    private var isRunning = false
    private var acceptTask: Task<Void, Never>?

    /// Callback for received hook events
    var onEvent: ((HookMessage) -> Void)?

    func start() throws {
        guard !isRunning else { return }

        // Remove stale socket file
        unlink(Self.socketPath)

        // Create socket
        listenSocket = socket(AF_UNIX, SOCK_STREAM, 0)
        guard listenSocket >= 0 else {
            throw HookReceiverError.socketCreationFailed(errno)
        }

        // Bind
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

        // Set permissions so hook scripts can connect
        chmod(Self.socketPath, 0o666)

        // Listen
        guard listen(listenSocket, 10) == 0 else {
            close(listenSocket)
            throw HookReceiverError.listenFailed(errno)
        }

        isRunning = true
        logger.info("Hook receiver listening on \(Self.socketPath)")

        // Accept connections in background
        let sock = listenSocket
        let receiver = self
        acceptTask = Task.detached {
            await receiver.acceptLoop(socket: sock)
        }
    }

    func stop() {
        guard isRunning else { return }
        isRunning = false
        acceptTask?.cancel()
        acceptTask = nil

        if listenSocket >= 0 {
            close(listenSocket)
            listenSocket = -1
        }
        unlink(Self.socketPath)
        logger.info("Hook receiver stopped")
    }

    private func acceptLoop(socket listenSock: Int32) async {
        while !Task.isCancelled {
            var clientAddr = sockaddr_un()
            var clientAddrLen = socklen_t(MemoryLayout<sockaddr_un>.size)

            let clientSocket = withUnsafeMutablePointer(to: &clientAddr) { ptr in
                ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockPtr in
                    accept(listenSock, sockPtr, &clientAddrLen)
                }
            }

            if clientSocket < 0 {
                if Task.isCancelled { break }
                continue
            }

            // Handle client in a separate task
            Task.detached { [weak self] in
                await self?.handleClient(socket: clientSocket)
            }
        }
    }

    private func handleClient(socket clientSocket: Int32) {
        defer { close(clientSocket) }

        // Read all data from the client
        var data = Data()
        let bufferSize = 4096
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
        defer { buffer.deallocate() }

        while true {
            let bytesRead = read(clientSocket, buffer, bufferSize)
            if bytesRead <= 0 { break }
            data.append(buffer, count: bytesRead)
        }

        guard !data.isEmpty else { return }

        // Parse NDJSON — each line is a separate JSON message
        let text = String(data: data, encoding: .utf8) ?? ""
        for line in text.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { continue }

            guard let lineData = trimmed.data(using: .utf8) else { continue }

            do {
                let message = try JSONDecoder().decode(HookMessage.self, from: lineData)
                logger.info("Received hook event: \(message.type.rawValue) for session \(message.sessionId ?? "unknown")")
                onEvent?(message)
            } catch {
                logger.error("Failed to parse hook message: \(error.localizedDescription) — raw: \(trimmed)")
            }
        }
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
