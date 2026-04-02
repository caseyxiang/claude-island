import SwiftUI

/// A single session card displayed in the expanded notch panel.
struct NotchSessionCard: View {
    let session: AgentSession
    var onTap: (() -> Void)?
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

            // Row 3: Pending prompt (permission / question)
            if let prompt = session.pendingPrompt {
                Text("> \(prompt)")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.orange.opacity(0.8))
                    .lineLimit(2)
            }

            // Row 4: Action buttons
            if session.status == .waitingPermission {
                HStack(spacing: 8) {
                    Button {
                        onTap?()  // Jump to terminal to approve
                    } label: {
                        Text("Allow")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.black)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 5)
                            .background(claudeOrange)
                            .cornerRadius(6)
                    }
                    .buttonStyle(.plain)

                    Button {
                        onTap?()  // Jump to terminal to deny
                    } label: {
                        Text("Deny")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.7))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 5)
                            .background(.white.opacity(0.08))
                            .cornerRadius(6)
                    }
                    .buttonStyle(.plain)

                    Spacer()

                    jumpButton
                }
                .padding(.top, 2)
            } else if session.status == .waitingAnswer {
                HStack {
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

    // MARK: - Status Dot

    @ViewBuilder
    private var statusDot: some View {
        if session.hasUnreadCompletion {
            // Breathing green glow — task just completed, unread
            Circle()
                .fill(.green)
                .frame(width: 8, height: 8)
                .shadow(color: .green.opacity(0.8), radius: breathe ? 6 : 2)
                .opacity(breathe ? 1.0 : 0.4)
                .animation(
                    .easeInOut(duration: 1.2).repeatForever(autoreverses: true),
                    value: breathe
                )
        } else if session.status.needsAttention {
            // Pulsing orange/yellow — needs user action
            Circle()
                .fill(statusColor)
                .frame(width: 8, height: 8)
                .shadow(color: statusColor.opacity(0.8), radius: breathe ? 6 : 2)
                .opacity(breathe ? 1.0 : 0.5)
                .animation(
                    .easeInOut(duration: 0.8).repeatForever(autoreverses: true),
                    value: breathe
                )
        } else {
            // Stable green — running normally
            Circle()
                .fill(.green)
                .frame(width: 7, height: 7)
        }
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
        case .running: .green
        case .waitingPermission: .orange
        case .waitingAnswer: .yellow
        case .stopped: .green.opacity(0.7)
        case .done: .gray
        }
    }

    private var statusText: String {
        if session.hasUnreadCompletion { return "COMPLETED" }
        switch session.status {
        case .running: return "RUNNING"
        case .waitingPermission: return "NEEDS INPUT"
        case .waitingAnswer: return "QUESTION"
        case .stopped: return "DONE"
        case .done: return "DONE"
        }
    }

    private var borderColor: Color {
        if session.hasUnreadCompletion { return .green.opacity(0.3) }
        if session.status.needsAttention { return statusColor.opacity(0.3) }
        return .clear
    }
}
