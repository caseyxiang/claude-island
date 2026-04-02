import SwiftUI

/// The content view displayed inside the floating Dynamic Island window.
struct DynamicIslandView: View {
    @Bindable var sessionManager: SessionManager
    @Bindable var diState: DynamicIslandState
    @State private var isExpanded = false
    @State private var hovering = false
    @State private var expandedContent: ExpandedContent?
    @State private var collapseTaskID = UUID()

    enum ExpandedContent {
        case attention(AgentSession)
        case completed(AgentSession)
    }

    var body: some View {
        VStack(spacing: 0) {
            if isExpanded, let content = expandedContent {
                switch content {
                case .attention(let session):
                    attentionExpandedView(session: session)
                case .completed(let session):
                    completedExpandedView(session: session)
                }
            } else {
                collapsedView
            }
        }
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: isExpanded ? 18 : 22))
        .shadow(color: .black.opacity(0.25), radius: 8, y: 4)
        .onHover { isHovering in
            hovering = isHovering
            // If user hovers while expanded, reset the auto-collapse timer
            if isHovering && isExpanded {
                collapseTaskID = UUID()
            }
            // When mouse leaves, schedule collapse
            if !isHovering && isExpanded {
                scheduleAutoCollapse()
            }
        }
        .onChange(of: sessionManager.attentionSessions.count) { _, newCount in
            if newCount > 0 {
                expand(with: .attention(sessionManager.attentionSessions.first!))
            }
        }
        .onChange(of: diState.pendingCompletion?.id) { _, newVal in
            if let session = diState.pendingCompletion {
                expand(with: .completed(session))
                diState.pendingCompletion = nil
            }
        }
    }

    // MARK: - Public: called by AppDelegate when task completes

    func showCompletion(session: AgentSession) {
        expand(with: .completed(session))
    }

    // MARK: - Expand / Collapse

    private func expand(with content: ExpandedContent) {
        expandedContent = content
        withAnimation(.spring(response: 0.4, dampingFraction: 0.75)) {
            isExpanded = true
        }
        scheduleAutoCollapse()
    }

    private func collapse() {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
            isExpanded = false
        }
        expandedContent = nil
    }

    private func scheduleAutoCollapse() {
        let taskID = UUID()
        collapseTaskID = taskID
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(10))
            // Only collapse if this is still the active timer and user isn't hovering
            guard collapseTaskID == taskID, !hovering else { return }
            collapse()
        }
    }

    // MARK: - Collapsed

    private var collapsedView: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(sessionManager.activeCount > 0 ? .blue : .gray)
                .frame(width: 8, height: 8)

            let count = sessionManager.activeCount

            if count > 0 {
                Text("\(count)")
                    .font(.system(.caption, design: .rounded, weight: .bold))
                    .monospacedDigit()

                Text(count == 1 ? "agent" : "agents")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            } else {
                Text("idle")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .onTapGesture {
            if let session = sessionManager.attentionSessions.first {
                expand(with: .attention(session))
            }
        }
    }

    // MARK: - Attention Expanded (permission / question)

    private func attentionExpandedView(session: AgentSession) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: session.status.iconName)
                    .foregroundStyle(session.status == .waitingPermission ? .orange : .yellow)

                Text(session.displayTitle)
                    .font(.system(.caption, design: .monospaced, weight: .bold))
                    .lineLimit(1)

                Spacer()

                closeButton
            }

            if let prompt = session.pendingPrompt {
                Text(prompt)
                    .font(.caption)
                    .lineLimit(3)
                    .foregroundStyle(.primary)
            }

            if session.status == .waitingPermission {
                HStack(spacing: 10) {
                    Button("Approve") { collapse() }
                        .buttonStyle(.borderedProminent)
                        .tint(.green)
                        .controlSize(.small)

                    Button("Reject") { collapse() }
                        .buttonStyle(.bordered)
                        .tint(.red)
                        .controlSize(.small)

                    Spacer()

                    jumpButton
                }
            } else {
                HStack {
                    Spacer()
                    jumpButton
                }
            }
        }
        .padding(14)
        .frame(width: 320)
    }

    // MARK: - Completed Expanded (task done)

    private func completedExpandedView(session: AgentSession) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)

                Text(session.displayTitle)
                    .font(.system(.caption, design: .monospaced, weight: .bold))
                    .lineLimit(1)

                Spacer()

                closeButton
            }

            Text("Task completed")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack {
                Text(session.duration)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)

                Spacer()

                jumpButton
            }
        }
        .padding(14)
        .frame(width: 320)
    }

    // MARK: - Shared buttons

    private var closeButton: some View {
        Button { collapse() } label: {
            Image(systemName: "xmark.circle.fill")
                .foregroundStyle(.secondary)
        }
        .buttonStyle(.plain)
    }

    private var jumpButton: some View {
        Button {
            // jump to terminal
            collapse()
        } label: {
            Image(systemName: "terminal")
            Text("Jump")
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
    }
}
