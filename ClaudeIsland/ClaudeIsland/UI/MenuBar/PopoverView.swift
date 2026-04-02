import SwiftUI

struct PopoverView: View {
    @Bindable var sessionManager: SessionManager
    var onJumpToTerminal: ((AgentSession) -> Void)?
    var onOpenSettings: (() -> Void)?

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()

            if sessionManager.sessions.isEmpty {
                emptyState
            } else {
                sessionList
            }

            Divider()
            footer
        }
        .frame(width: 360)
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Image(systemName: "bolt.circle.fill")
                .foregroundStyle(.blue)
            Text("Claude Island")
                .font(.headline)

            Spacer()

            if sessionManager.activeCount > 0 {
                Text("\(sessionManager.activeCount) active")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(.blue.opacity(0.1), in: Capsule())
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "cloud.sun")
                .font(.system(size: 32))
                .foregroundStyle(.secondary)
            Text("No active sessions")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text("Start a Claude Code session in any terminal")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 30)
    }

    // MARK: - Session List

    private var sessionList: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                // Attention-needed sessions first
                ForEach(sessionManager.attentionSessions) { session in
                    SessionRowView(session: session)
                        .background(.orange.opacity(0.05))
                        .onTapGesture { onJumpToTerminal?(session) }
                }

                // Then running sessions
                ForEach(sessionManager.activeSessions.filter { !$0.status.needsAttention }) { session in
                    SessionRowView(session: session)
                        .onTapGesture { onJumpToTerminal?(session) }
                }
            }
        }
        .frame(maxHeight: 320)
    }

    // MARK: - Footer

    private var footer: some View {
        HStack {
            Button {
                onOpenSettings?()
            } label: {
                Image(systemName: "gear")
                Text("Settings")
            }
            .buttonStyle(.plain)
            .font(.caption)

            Spacer()

            Button("Quit") {
                NSApplication.shared.terminate(nil)
            }
            .buttonStyle(.plain)
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }
}
