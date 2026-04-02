import Foundation

// MARK: - Hook Events (received via Unix Domain Socket)

enum HookEventType: String, Codable {
    case stop
    case permission
    case question
}

struct HookMessage: Codable {
    let type: HookEventType
    let sessionId: String?
    let pid: Int?
    let toolName: String?
    let toolInput: String?
    let question: String?
    let transcriptPath: String?
    let cwd: String?
}
