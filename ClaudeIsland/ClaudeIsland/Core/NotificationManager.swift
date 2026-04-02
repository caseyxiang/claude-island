import Foundation
import UserNotifications
import OSLog

/// Manages system notifications for Claude Code agent events.
final class NotificationManager: NSObject, UNUserNotificationCenterDelegate {
    private let logger = Logger(subsystem: "com.claudeisland", category: "Notifications")
    private var center: UNUserNotificationCenter?

    static let approveAction = "APPROVE_ACTION"
    static let rejectAction = "REJECT_ACTION"
    static let jumpAction = "JUMP_ACTION"
    static let permissionCategory = "PERMISSION_REQUEST"
    static let questionCategory = "QUESTION_ASKED"
    static let taskDoneCategory = "TASK_DONE"

    var onApprove: ((String) -> Void)?  // sessionId
    var onReject: ((String) -> Void)?   // sessionId
    var onJump: ((String) -> Void)?     // sessionId

    func setup() {
        // UNUserNotificationCenter crashes if the app is not a proper .app bundle
        // (e.g., when running via `swift build` / SPM debug binary)
        guard Bundle.main.bundleIdentifier != nil else {
            logger.warning("Skipping notification setup — app is not bundled")
            return
        }
        let c = UNUserNotificationCenter.current()
        center = c
        c.delegate = self
        registerCategories()
    }

    func requestPermission() {
        guard let center else { return }
        center.requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
            if granted {
                self.logger.info("Notification permission granted")
            } else if let error {
                self.logger.error("Notification permission error: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Send Notifications

    func notifyPermissionNeeded(session: AgentSession) {
        let content = UNMutableNotificationContent()
        content.title = "Agent needs permission"
        content.subtitle = session.workspaceName
        content.body = session.pendingPrompt ?? "Allow \(session.pendingToolName ?? "tool")?"
        content.sound = .default
        content.categoryIdentifier = Self.permissionCategory
        content.userInfo = ["sessionId": session.sessionId]

        let request = UNNotificationRequest(
            identifier: "permission-\(session.sessionId)",
            content: content,
            trigger: nil
        )
        center?.add(request)
    }

    func notifyQuestionAsked(session: AgentSession) {
        let content = UNMutableNotificationContent()
        content.title = "Agent has a question"
        content.subtitle = session.workspaceName
        content.body = session.pendingPrompt ?? "Claude is asking you a question"
        content.sound = .default
        content.categoryIdentifier = Self.questionCategory
        content.userInfo = ["sessionId": session.sessionId]

        let request = UNNotificationRequest(
            identifier: "question-\(session.sessionId)",
            content: content,
            trigger: nil
        )
        center?.add(request)
    }

    func notifyTaskDone(session: AgentSession) {
        let content = UNMutableNotificationContent()
        content.title = "Task completed"
        content.subtitle = session.workspaceName
        content.body = "Claude Code has finished working."
        content.sound = UNNotificationSound(named: UNNotificationSoundName("Hero"))
        content.categoryIdentifier = Self.taskDoneCategory
        content.userInfo = ["sessionId": session.sessionId]

        let request = UNNotificationRequest(
            identifier: "done-\(session.sessionId)",
            content: content,
            trigger: nil
        )
        center?.add(request)
    }

    // MARK: - Categories

    private func registerCategories() {
        let approveAction = UNNotificationAction(
            identifier: Self.approveAction,
            title: "Approve",
            options: [.foreground]
        )
        let rejectAction = UNNotificationAction(
            identifier: Self.rejectAction,
            title: "Reject",
            options: [.destructive]
        )
        let jumpAction = UNNotificationAction(
            identifier: Self.jumpAction,
            title: "Jump to Terminal",
            options: [.foreground]
        )

        let permissionCategory = UNNotificationCategory(
            identifier: Self.permissionCategory,
            actions: [approveAction, rejectAction, jumpAction],
            intentIdentifiers: []
        )
        let questionCategory = UNNotificationCategory(
            identifier: Self.questionCategory,
            actions: [jumpAction],
            intentIdentifiers: []
        )
        let taskDoneCategory = UNNotificationCategory(
            identifier: Self.taskDoneCategory,
            actions: [jumpAction],
            intentIdentifiers: []
        )

        center?.setNotificationCategories([permissionCategory, questionCategory, taskDoneCategory])
    }

    // MARK: - Delegate

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let sessionId = response.notification.request.content.userInfo["sessionId"] as? String ?? ""

        switch response.actionIdentifier {
        case Self.approveAction:
            onApprove?(sessionId)
        case Self.rejectAction:
            onReject?(sessionId)
        case Self.jumpAction:
            onJump?(sessionId)
        default:
            // Default tap — jump to terminal
            onJump?(sessionId)
        }

        completionHandler()
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }
}
