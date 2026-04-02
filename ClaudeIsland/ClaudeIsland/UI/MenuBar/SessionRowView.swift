import SwiftUI

struct SessionRowView: View {
    let session: AgentSession

    var body: some View {
        HStack(spacing: 10) {
            // Status indicator
            statusIcon

            // Session info
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(session.displayTitle)
                        .font(.system(.body, design: .monospaced, weight: .semibold))
                        .lineLimit(1)

                    Spacer()

                    Text(session.timeAgo)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                // Status line
                statusLine

                // Bottom row: entrypoint + duration
                HStack {
                    Text(session.entrypoint)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)

                    Spacer()

                    Text(session.duration)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 10)
        .contentShape(Rectangle())
    }

    // MARK: - Status Icon

    @ViewBuilder
    private var statusIcon: some View {
        switch session.status {
        case .working, .idle:
            Circle()
                .fill(.green)
                .frame(width: 10, height: 10)
                .overlay {
                    Circle()
                        .stroke(.green.opacity(0.3), lineWidth: 2)
                        .scaleEffect(1.8)
                }

        case .waitingPermission, .waitingAnswer:
            Circle()
                .fill(session.status == .waitingPermission ? .orange : .yellow)
                .frame(width: 10, height: 10)
                .overlay {
                    Circle()
                        .stroke((session.status == .waitingPermission ? Color.orange : .yellow).opacity(0.5), lineWidth: 2)
                        .scaleEffect(pulseAnimation ? 1.8 : 1.2)
                        .opacity(pulseAnimation ? 0 : 0.8)
                        .animation(
                            .easeInOut(duration: 1.0).repeatForever(autoreverses: false),
                            value: pulseAnimation
                        )
                }
                .onAppear { pulseAnimation = true }

        case .done:
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 14))
                .foregroundStyle(.green.opacity(0.7))
        }
    }

    @State private var pulseAnimation = false

    // MARK: - Status Line

    @ViewBuilder
    private var statusLine: some View {
        switch session.status {
        case .working, .idle:
            Text("Running")
                .font(.caption)
                .foregroundStyle(.green)

        case .waitingPermission:
            Text(session.pendingPrompt ?? "Needs permission")
                .font(.caption)
                .foregroundStyle(.orange)
                .lineLimit(2)

        case .waitingAnswer:
            Text(session.pendingPrompt ?? "Asking a question")
                .font(.caption)
                .foregroundStyle(.yellow)
                .lineLimit(2)

        case .done:
            Text("Task completed")
                .font(.caption)
                .foregroundStyle(.secondary)

        case .done:
            Text("Done")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}
