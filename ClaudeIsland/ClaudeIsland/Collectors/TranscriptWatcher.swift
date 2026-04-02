import Foundation
import OSLog

/// Incrementally reads Claude Code transcript (.jsonl) files to extract
/// the latest assistant response and user prompt for live display.
final class TranscriptWatcher {
    private let logger = Logger(subsystem: "com.claudeisland", category: "TranscriptWatcher")
    private var watchers: [String: TranscriptFileWatcher] = [:]
    private var timer: Timer?

    /// Callback with (sessionId, latestResponse, lastUserPrompt)
    var onResponseUpdate: ((String, String, String?) -> Void)?
    /// Callback when file growth status changes (sessionId, isGrowing)
    var onActivityChange: ((String, Bool) -> Void)?

    func startWatching(sessionId: String, transcriptPath: String, readRecent: Bool = false) {
        guard watchers[sessionId] == nil else { return }
        watchers[sessionId] = TranscriptFileWatcher(path: transcriptPath, readRecent: readRecent)
    }

    func stopWatching(sessionId: String) {
        watchers.removeValue(forKey: sessionId)
    }

    func start() {
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.pollAll()
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        watchers.removeAll()
    }

    private var lastGrowingState: [String: Bool] = [:]

    private func pollAll() {
        for (sessionId, watcher) in watchers {
            let (response, prompt) = watcher.readLatest()
            if let response {
                onResponseUpdate?(sessionId, response, prompt)
            }

            // Report activity changes
            let growing = watcher.isGrowing
            if lastGrowingState[sessionId] != growing {
                lastGrowingState[sessionId] = growing
                onActivityChange?(sessionId, growing)
            }
        }
    }
}

/// Watches a single transcript file with incremental reading.
private final class TranscriptFileWatcher {
    let path: String
    private var lastOffset: UInt64 = 0
    private var lastText: String = ""

    private var growCount = 0  // consecutive polls where file grew

    var isGrowing: Bool {
        growCount >= 2  // must grow for 2+ consecutive seconds to count
    }

    init(path: String, readRecent: Bool = false) {
        self.path = path
        if let attrs = try? FileManager.default.attributesOfItem(atPath: path),
           let size = attrs[.size] as? UInt64 {
            if readRecent {
                lastOffset = size > 32768 ? size - 32768 : 0
            } else {
                lastOffset = size
            }
        }
    }

    /// Returns (latestAssistantResponse, lastUserPrompt)
    func readLatest() -> (String?, String?) {
        guard let handle = FileHandle(forReadingAtPath: path) else { return (nil, nil) }
        defer { handle.closeFile() }

        handle.seekToEndOfFile()
        let fileSize = handle.offsetInFile
        if fileSize > lastOffset {
            growCount += 1
        } else {
            growCount = 0
            return (nil, nil)
        }
        lastOffset = fileSize

        let readFrom: UInt64 = fileSize > 32768 ? fileSize - 32768 : 0
        handle.seek(toFileOffset: readFrom)
        let data = handle.readDataToEndOfFile()

        guard let text = String(data: data, encoding: .utf8) else { return (nil, nil) }

        var latestResponse: String?
        var latestPrompt: String?

        for line in text.components(separatedBy: .newlines).reversed() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { continue }
            guard let lineData = trimmed.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any] else {
                continue
            }

            let type = json["type"] as? String

            // Latest assistant response
            if type == "assistant" && latestResponse == nil {
                if let message = json["message"] as? [String: Any],
                   let content = message["content"] as? [[String: Any]] {
                    var texts: [String] = []
                    for block in content {
                        if (block["type"] as? String) == "text",
                           let t = block["text"] as? String {
                            texts.append(t)
                        }
                    }
                    if !texts.isEmpty {
                        let combined = texts.joined(separator: " ")
                        let cut = combined.count > 300 ? String(combined.suffix(300)) : combined
                        latestResponse = cut
                    }
                }
            }

            // Latest user prompt
            if type == "user" && latestPrompt == nil {
                if let message = json["message"] as? [String: Any],
                   let content = message["content"] as? [[String: Any]] {
                    for block in content {
                        if (block["type"] as? String) == "text",
                           let rawText = block["text"] as? String {
                            var cleaned = rawText
                            cleaned = cleaned.replacingOccurrences(of: "<[^>]+>[\\s\\S]*?</[^>]+>", with: "", options: .regularExpression)
                            cleaned = cleaned.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
                            cleaned = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
                            if !cleaned.isEmpty {
                                let firstLine = cleaned.components(separatedBy: .newlines).first ?? cleaned
                                latestPrompt = String(firstLine.prefix(150))
                                break
                            }
                        }
                    }
                }
            }

            if latestResponse != nil && latestPrompt != nil { break }
        }

        if let resp = latestResponse, resp != lastText {
            lastText = resp
            return (resp, latestPrompt)
        }
        return (nil, nil)
    }
}
