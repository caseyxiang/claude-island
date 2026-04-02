import AppKit
import SwiftUI
import OSLog

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let logger = Logger(subsystem: "com.claudeisland", category: "AppDelegate")

    let sessionManager = SessionManager()
    let notificationManager = NotificationManager()
    let notchPanelManager = NotchPanelManager()
    let diState = DynamicIslandState()

    // Menu bar is removed — notch panel handles all UI now

    // MARK: - App Lifecycle

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Hide dock icon — menu bar only app
        NSApp.setActivationPolicy(.accessory)

        // Install hooks on first launch
        installHooksIfNeeded()

        // Setup and request notification permission
        notificationManager.setup()
        notificationManager.requestPermission()

        // Setup Notch Panel
        notchPanelManager.onJumpToTerminal = { [weak self] session in
            self?.jumpToTerminal(session)
        }
        notchPanelManager.show(sessionManager: sessionManager, diState: diState)

        // Wire up notifications
        wireNotifications()

        // Start session monitoring
        sessionManager.start()

        logger.info("Claude Island launched")
    }

    func applicationWillTerminate(_ notification: Notification) {
        sessionManager.stop()
        notchPanelManager.hide()
    }

    // MARK: - Hooks Installation

    private func installHooksIfNeeded() {
        guard !HookInstaller.isInstalled else {
            logger.info("Hooks already installed")
            return
        }

        do {
            try HookInstaller.install()
            logger.info("Hooks installed successfully")
        } catch {
            logger.error("Failed to install hooks: \(error.localizedDescription)")
        }
    }

    // MARK: - Notifications Wiring

    private func wireNotifications() {
        sessionManager.onAttentionNeeded = { [weak self] session in
            guard let self else { return }
            switch session.status {
            case .waitingPermission:
                notificationManager.notifyPermissionNeeded(session: session)
            case .waitingAnswer:
                notificationManager.notifyQuestionAsked(session: session)
            default:
                break
            }
            // Notch peek
            notchPanelManager.showPeek(session: session)
        }

        sessionManager.onSessionCompleted = { [weak self] session in
            guard let self else { return }
            notificationManager.notifyTaskDone(session: session)
            notchPanelManager.showCompletion(session: session)
        }

        notificationManager.onJump = { [weak self] sessionId in
            guard let session = self?.sessionManager.sessions.first(where: { $0.sessionId == sessionId }) else { return }
            self?.jumpToTerminal(session)
        }
    }

    // MARK: - Terminal Jump

    private func jumpToTerminal(_ session: AgentSession) {
        logger.info("Jumping to: \(session.displayTitle), entrypoint: \(session.entrypoint), pid: \(session.pid)")

        switch session.entrypoint {
        case "claude-vscode":
            jumpToVSCodeWindow(cwd: session.cwd)
        case "claude-cursor":
            jumpToEditorWindow(appName: "Cursor", cwd: session.cwd)
        default:
            let appName = terminalAppForPid(session.pid) ?? "Terminal"
            activateApp(appName)
        }
    }

    /// Open the specific VS Code window matching the workspace path
    private func jumpToVSCodeWindow(cwd: String) {
        // Use vscode:// URI scheme to open/focus the specific folder
        let encoded = cwd.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? cwd
        if let url = URL(string: "vscode://file\(encoded)") {
            NSWorkspace.shared.open(url)
        } else {
            activateApp("Visual Studio Code")
        }
    }

    private func jumpToEditorWindow(appName: String, cwd: String) {
        let cliName = appName.lowercased()
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        task.arguments = [cliName, cwd]
        task.standardOutput = FileHandle.nullDevice
        task.standardError = FileHandle.nullDevice
        do {
            try task.run()
        } catch {
            activateApp(appName)
        }
    }

    private func activateApp(_ appName: String) {
        let script = """
        tell application "\(appName)"
            activate
        end tell
        """
        if let appleScript = NSAppleScript(source: script) {
            var error: NSDictionary?
            appleScript.executeAndReturnError(&error)
            if let error {
                logger.error("AppleScript error: \(error)")
            }
        }
    }

    private func terminalAppForPid(_ pid: Int) -> String? {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/ps")
        task.arguments = ["-p", "\(pid)", "-o", "ppid="]
        let pipe = Pipe()
        task.standardOutput = pipe

        do {
            try task.run()
            task.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            if let output = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
               let ppid = Int(output) {
                let nameTask = Process()
                nameTask.executableURL = URL(fileURLWithPath: "/bin/ps")
                nameTask.arguments = ["-p", "\(ppid)", "-o", "comm="]
                let namePipe = Pipe()
                nameTask.standardOutput = namePipe
                try nameTask.run()
                nameTask.waitUntilExit()
                let nameData = namePipe.fileHandleForReading.readDataToEndOfFile()
                if let name = String(data: nameData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) {
                    if name.contains("iTerm") { return "iTerm2" }
                    if name.contains("Terminal") { return "Terminal" }
                    if name.contains("Warp") { return "Warp" }
                    if name.contains("Ghostty") { return "Ghostty" }
                    if name.contains("Code") { return "Visual Studio Code" }
                    if name.contains("Cursor") { return "Cursor" }
                }
            }
        } catch {
            logger.error("Failed to determine terminal for pid \(pid): \(error)")
        }
        return nil
    }

    // MARK: - Settings

    private func openSettings() {
        NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
    }
}
