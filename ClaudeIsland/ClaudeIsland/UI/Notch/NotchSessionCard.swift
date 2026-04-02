import SwiftUI

/// A single session card displayed in the expanded notch panel.
struct NotchSessionCard: View {
    let session: AgentSession
    var onTap: (() -> Void)?
    var onApprove: (() -> Void)?
    var onDeny: (() -> Void)?
    @State private var breathe = false
    @State private var isHovering = false

    private let claudeOrange = Color(red: 0.85, green: 0.47, blue: 0.34)

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Row 1: Status dot + Title + Status tag
            HStack(spacing: 8) {
                statusDot

                Text(session.displayTitle)
                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                    .foregroundStyle(.white)
                    .lineLimit(1)

                Spacer()

                Text(statusText)
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(statusColor)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(statusColor.opacity(0.12))
                    .cornerRadius(4)
            }

            // Row 2: Workspace + duration
            HStack {
                Text(session.workspaceName)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.35))
                    .lineLimit(1)

                Spacer()

                Text(session.duration)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.35))
            }

            // Row 3: Context info based on state
            if session.status.needsAttention {
                // Permission / question: show user prompt for context, then the pending action
                if let userPrompt = session.lastUserPrompt, !userPrompt.isEmpty {
                    HStack(alignment: .top, spacing: 4) {
                        Text("You:")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(claudeOrange.opacity(0.8))
                        Text(userPrompt)
                            .font(.system(size: 9))
                            .foregroundStyle(.white.opacity(0.5))
                            .lineLimit(1)
                    }
                }
                if let prompt = session.pendingPrompt {
                    Text("> \(prompt)")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.orange.opacity(0.8))
                        .lineLimit(2)
                }
            } else if session.status == .working {
                // Working: show prompt + live streaming response
                if let userPrompt = session.lastUserPrompt, !userPrompt.isEmpty {
                    HStack(alignment: .top, spacing: 4) {
                        Text("You:")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(claudeOrange.opacity(0.8))
                        Text(userPrompt)
                            .font(.system(size: 9))
                            .foregroundStyle(.white.opacity(0.5))
                            .lineLimit(1)
                    }
                }
                if let live = session.liveResponse, !live.isEmpty {
                    Text(live)
                        .font(.system(size: 9))
                        .foregroundStyle(.green.opacity(0.6))
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            } else if session.hasUnreadCompletion || session.status == .idle {
                // Completed/idle: show last prompt and final response
                if let userPrompt = session.lastUserPrompt, !userPrompt.isEmpty {
                    HStack(alignment: .top, spacing: 4) {
                        Text("You:")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(claudeOrange.opacity(0.7))
                        Text(userPrompt)
                            .font(.system(size: 9))
                            .foregroundStyle(.white.opacity(0.4))
                            .lineLimit(1)
                    }
                }
                if let response = session.lastAssistantMessage, !response.isEmpty {
                    Text(response)
                        .font(.system(size: 9))
                        .foregroundStyle(.green.opacity(0.6))
                        .lineLimit(3)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }

            // Row 4: Action buttons (both permission and question show Jump)
            if session.status.needsAttention {
                HStack(spacing: 8) {
                    if session.status == .waitingPermission {
                        Button { onApprove?() } label: {
                            Text("Allow")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(.black)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 5)
                                .background(Color.green)
                                .cornerRadius(6)
                        }
                        .buttonStyle(.plain)

                        Button { onDeny?() } label: {
                            Text("Deny")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(.white.opacity(0.7))
                                .padding(.horizontal, 12)
                                .padding(.vertical, 5)
                                .background(.red.opacity(0.3))
                                .cornerRadius(6)
                        }
                        .buttonStyle(.plain)
                    }

                    Spacer()

                    jumpButton
                }
                .padding(.top, 2)
            }
        }
        .padding(10)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(borderColor, lineWidth: borderColor == .clear ? 0 : 1)
        )
        .onHover { isHovering = $0 }
        .background(isHovering ? Color.white.opacity(0.08) : Color.white.opacity(0.04))
        .cornerRadius(10)
        .contentShape(Rectangle())
        .onTapGesture {
            onTap?()
        }
        .onAppear { breathe = true }
    }

    // MARK: - Status Icon

    private var statusDot: some View {
        PixelIconView(session: session, size: 28)
    }

    // MARK: - Jump Button

    private var jumpButton: some View {
        Button {
            onTap?()
        } label: {
            HStack(spacing: 3) {
                Image(systemName: "terminal")
                    .font(.system(size: 9))
                Text("Jump")
                    .font(.system(size: 10, weight: .medium))
            }
            .foregroundStyle(.white.opacity(0.6))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(.white.opacity(0.06))
            .cornerRadius(6)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Colors

    private var statusColor: Color {
        switch session.status {
        case .working: .green
        case .idle: .gray
        case .waitingPermission, .waitingAnswer: .orange
        case .done: .gray
        }
    }

    private var statusText: String {
        if session.hasUnreadCompletion { return "COMPLETED" }
        switch session.status {
        case .working: return "WORKING"
        case .idle: return "IDLE"
        case .waitingPermission, .waitingAnswer: return "NEEDS INPUT"
        case .done: return "DONE"
        }
    }

    private var borderColor: Color {
        if session.hasUnreadCompletion { return .green.opacity(0.3) }
        if session.status.needsAttention { return statusColor.opacity(0.3) }
        return .clear
    }
}
