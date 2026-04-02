import Foundation

// MARK: - Hook Events (received via Unix Domain Socket)

enum HookEventType: String, Codable {
    case stop
    case permission
    case question
    case userPrompt   // user submitted a new prompt
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
    let hookStatus: String?
    let lastPrompt: String?
    let lastResponse: String?
    let waitingApproval: Bool?

    enum CodingKeys: String, CodingKey {
        case type, sessionId, pid, toolName, toolInput, question, transcriptPath, cwd
        case hookStatus = "status"
        case lastPrompt, lastResponse, waitingApproval
    }
}
