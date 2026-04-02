import Foundation
import OSLog

/// Watches ~/.claude/sessions/ for session file changes using DispatchSource (FSEvents).
/// Detects new sessions starting and sessions ending.
@Observable
final class FileWatcher {
    private let logger = Logger(subsystem: "com.claudeisland", category: "FileWatcher")
    private let sessionsPath: String
    private var source: DispatchSourceFileSystemObject?
    private var fileDescriptor: Int32 = -1
    private var pollTimer: Timer?
    private var knownFiles: [String: SessionFile] = [:]

    /// Callback when a new session is discovered
    var onSessionDiscovered: ((SessionFile) -> Void)?
    /// Callback when a session file is removed
    var onSessionRemoved: ((String) -> Void)?

    init() {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        self.sessionsPath = "\(home)/.claude/sessions"
    }

    func start() {
        // Ensure directory exists
        try? FileManager.default.createDirectory(
            atPath: sessionsPath,
            withIntermediateDirectories: true
        )

        // Initial scan
        scanDirectory()

        // Watch for changes using DispatchSource
        fileDescriptor = open(sessionsPath, O_EVTONLY)
        guard fileDescriptor >= 0 else {
            logger.error("Failed to open sessions directory for watching")
            startPolling()
            return
        }

        source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fileDescriptor,
            eventMask: [.write, .delete, .rename],
            queue: .main
        )

        source?.setEventHandler { [weak self] in
            self?.scanDirectory()
        }

        source?.setCancelHandler { [weak self] in
            if let fd = self?.fileDescriptor, fd >= 0 {
                close(fd)
                self?.fileDescriptor = -1
            }
        }

        source?.resume()
        logger.info("File watcher started on \(self.sessionsPath)")

        // Also poll periodically for liveness checks
        startPolling()
    }

    func stop() {
        source?.cancel()
        source = nil
        pollTimer?.invalidate()
        pollTimer = nil
        if fileDescriptor >= 0 {
            close(fileDescriptor)
            fileDescriptor = -1
        }
        logger.info("File watcher stopped")
    }

    private func startPolling() {
        pollTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            self?.scanDirectory()
        }
    }

    func scanDirectory() {
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(atPath: sessionsPath) else { return }

        let jsonFiles = Set(files.filter { $0.hasSuffix(".json") })
        let knownFileNames = Set(knownFiles.keys)

        // Detect new files
        for fileName in jsonFiles.subtracting(knownFileNames) {
            let filePath = "\(sessionsPath)/\(fileName)"
            guard let data = fm.contents(atPath: filePath),
                  let session = try? JSONDecoder().decode(SessionFile.self, from: data) else {
                continue
            }
            knownFiles[fileName] = session
            logger.info("Discovered session: pid=\(session.pid) id=\(session.sessionId)")
            onSessionDiscovered?(session)
        }

        // Detect removed files
        for fileName in knownFileNames.subtracting(jsonFiles) {
            if let session = knownFiles.removeValue(forKey: fileName) {
                logger.info("Session file removed: pid=\(session.pid)")
                onSessionRemoved?(session.sessionId)
            }
        }
    }

    /// Force re-read of all session files
    func rescan() {
        knownFiles.removeAll()
        scanDirectory()
    }
}
