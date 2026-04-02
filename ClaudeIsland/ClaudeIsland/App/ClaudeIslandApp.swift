import SwiftUI

@main
struct ClaudeIslandApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        // No main window — this is a menu bar only app
        Settings {
            SettingsView(sessionManager: appDelegate.sessionManager)
        }
    }
}
