import Foundation

/// Shared state between DynamicIslandView and AppDelegate.
/// Used to push events (like task completion) into the DI view.
@Observable
final class DynamicIslandState {
    var pendingCompletion: AgentSession?

    func showCompletion(session: AgentSession) {
        pendingCompletion = session
    }
}
