import SwiftUI

struct SettingsView: View {
    @Bindable var sessionManager: SessionManager
    @AppStorage("launchAtLogin") private var launchAtLogin = false
    @AppStorage("showDynamicIsland") private var showDynamicIsland = true
    @AppStorage("playSound") private var playSound = true
    @AppStorage("showNotifications") private var showNotifications = true

    var body: some View {
        TabView {
            generalTab
                .tabItem {
                    Label("General", systemImage: "gear")
                }

            hooksTab
                .tabItem {
                    Label("Hooks", systemImage: "link")
                }

            aboutTab
                .tabItem {
                    Label("About", systemImage: "info.circle")
                }
        }
        .frame(width: 420, height: 320)
    }

    // MARK: - General

    private var generalTab: some View {
        Form {
            Toggle("Launch at login", isOn: $launchAtLogin)

            Section("Notifications") {
                Toggle("Show system notifications", isOn: $showNotifications)
                Toggle("Play sound alerts", isOn: $playSound)
                Toggle("Show Dynamic Island", isOn: $showDynamicIsland)
            }
        }
        .formStyle(.grouped)
        .padding()
    }

    // MARK: - Hooks

    private var hooksTab: some View {
        Form {
            Section {
                HStack {
                    Image(systemName: HookInstaller.isInstalled ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .foregroundStyle(HookInstaller.isInstalled ? .green : .red)
                    Text(HookInstaller.isInstalled ? "Hooks are installed" : "Hooks not installed")
                }

                Button("Reinstall Hooks") {
                    try? HookInstaller.install()
                }

                Button("Remove Hooks") {
                    try? HookInstaller.uninstall()
                }
                .foregroundStyle(.red)
            } header: {
                Text("Claude Code Integration")
            } footer: {
                Text("Hooks are added to ~/.claude/settings.json and coexist with other tools.")
                    .font(.caption)
            }
        }
        .formStyle(.grouped)
        .padding()
    }

    // MARK: - About

    private var aboutTab: some View {
        VStack(spacing: 12) {
            Image(systemName: "bolt.circle.fill")
                .font(.system(size: 48))
                .foregroundStyle(.blue)

            Text("Claude Island")
                .font(.title2.bold())

            Text("v1.0.0")
                .foregroundStyle(.secondary)

            Text("Monitor your Claude Code agents from the menu bar.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Spacer()
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
