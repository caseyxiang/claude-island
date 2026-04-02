import SwiftUI

/// Root view inside the NotchPanel. Fills the full window width.
/// Content is clipped to NotchShape which overlaps with the hardware notch.
struct NotchContentView: View {
    @Bindable var sessionManager: SessionManager
    @Bindable var panelManager: NotchPanelManager
    @Bindable var diState: DynamicIslandState

    @State private var hovering = false

    private let claudeOrange = Color(red: 0.85, green: 0.47, blue: 0.34)

    // Corner radii (matches Notchi's approach)
    private var topCR: CGFloat { panelManager.isExpanded ? 19 : 6 }
    private var bottomCR: CGFloat { panelManager.isExpanded ? 24 : 14 }

    // Total width of the visible shape
    private var shapeWidth: CGFloat {
        if panelManager.isExpanded {
            return 480
        } else if panelManager.showingPeek {
            return panelManager.notchSize.width + 40
        } else {
            // Collapsed: show agent count + duration, needs ~220px
            return max(panelManager.notchSize.width + 4, 220)
        }
    }

    // Total height of the visible shape
    private var shapeHeight: CGFloat {
        if panelManager.isExpanded {
            return min(CGFloat(sessionManager.sessions.count) * 78 + 56, 380)
        } else if panelManager.showingPeek {
            return 36
        } else {
            return 30
        }
    }

    var body: some View {
        // Content fills the full window, top-aligned
        VStack(spacing: 0) {
            // The notch island: black shape + content
            ZStack(alignment: .top) {
                // Black background clipped to NotchShape
                Color.black
                    .frame(width: shapeWidth, height: shapeHeight)
                    .clipShape(
                        NotchShape(topCornerRadius: topCR, bottomCornerRadius: bottomCR)
                    )
                    .shadow(color: alertGlowColor, radius: alertGlowRadius, y: 4)

                // Content positioned below the notch area
                VStack(spacing: 0) {
                    if panelManager.isExpanded {
                        expandedContent
                    } else if panelManager.showingPeek {
                        peekContent
                    } else {
                        collapsedContent
                    }
                }
                .frame(width: shapeWidth)
                .clipped()
            }
            .onHover { hovering = $0 }
            .onChange(of: shapeWidth) { _, _ in syncDimensions() }
            .onChange(of: shapeHeight) { _, _ in syncDimensions() }
            .onAppear { syncDimensions() }
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .animation(.spring(response: 0.35, dampingFraction: 0.75), value: panelManager.isExpanded)
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: panelManager.showingPeek)
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: sessionManager.sessions.count)
        .onChange(of: diState.pendingCompletion?.id) { _, _ in
            if let session = diState.pendingCompletion {
                panelManager.showCompletion(session: session)
                diState.pendingCompletion = nil
            }
        }
        .onChange(of: sessionManager.attentionSessions.count) { _, newCount in
            if newCount > 0, let session = sessionManager.attentionSessions.first {
                panelManager.showPeek(session: session)
            }
        }
        .onChange(of: sessionManager.sessions.count) { _, count in
            panelManager.updateSessionCount(count)
        }
    }

    private func syncDimensions() {
        panelManager.currentShapeWidth = shapeWidth
        panelManager.currentShapeHeight = shapeHeight
    }

    // MARK: - Alert Glow

    private var alertGlowColor: Color {
        if sessionManager.attentionSessions.count > 0 { return .orange.opacity(0.4) }
        if panelManager.showingPeek { return .green.opacity(0.25) }
        return .clear
    }

    private var alertGlowRadius: CGFloat {
        (sessionManager.attentionSessions.count > 0 || panelManager.showingPeek) ? 16 : 0
    }

    // MARK: - Collapsed (tiny chin below notch with dots)

    private var collapsedContent: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(sessionManager.activeCount > 0 ? .green : .gray.opacity(0.5))
                .frame(width: 7, height: 7)

            if sessionManager.activeCount > 0 {
                Text("\(sessionManager.activeCount) agents")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
            } else {
                Text("idle")
                    .font(.system(size: 11, design: .rounded))
                    .foregroundStyle(.white.opacity(0.5))
            }

            if let longest = sessionManager.activeSessions.first {
                Text("·")
                    .foregroundStyle(.white.opacity(0.3))
                Text(longest.duration)
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.5))
            }
        }
        .frame(height: 26)
        .frame(maxWidth: .infinity)
        .background(Color.black.opacity(0.001))
        .onTapGesture {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                panelManager.expand()
            }
        }
    }

    // MARK: - Peek (notification bar)

    private var peekContent: some View {
        VStack(spacing: 0) {
            if let session = panelManager.alertSession {
                HStack(spacing: 6) {
                    Image(systemName: session.status.needsAttention ? session.status.iconName : "checkmark.circle.fill")
                        .foregroundStyle(session.status.needsAttention ? .orange : .green)
                        .font(.system(size: 11))

                    Text(session.displayTitle)
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .foregroundStyle(.white)
                        .lineLimit(1)

                    Spacer()

                    Text(session.status.needsAttention ? "INPUT" : "DONE")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(session.status.needsAttention ? .orange : .green)

                    Button { panelManager.dismissPeek() } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 7, weight: .bold))
                            .foregroundStyle(.white.opacity(0.3))
                    }
                    .buttonStyle(.plain)
                }
                .background(Color.black.opacity(0.001))
                .onTapGesture {
                    panelManager.onJumpToTerminal?(session)
                    panelManager.dismissPeek()
                }
            }
        }
        .frame(height: 36)
    }

    // MARK: - Expanded (full session list)

    private var expandedContent: some View {
        let inset = topCR + 6

        return VStack(spacing: 0) {
            // Header
            HStack {
                Text("Claude Code")
                    .font(.system(size: 13, weight: .semibold, design: .serif))
                    .foregroundStyle(claudeOrange)

                Spacer()

                Text("\(sessionManager.activeCount) Active")
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.4))
            }
            .padding(.horizontal, inset)
            .padding(.vertical, 6)
            .background(Color.black.opacity(0.001))
            .onTapGesture {
                withAnimation(.spring(response: 0.45, dampingFraction: 1.0)) {
                    panelManager.collapse()
                }
            }

            Divider()
                .background(Color.white.opacity(0.06))
                .padding(.horizontal, inset)

            // Sessions
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 8) {
                    ForEach(sessionManager.sessions) { session in
                        NotchSessionCard(session: session) {
                            sessionManager.markAsRead(session)
                            panelManager.onJumpToTerminal?(session)
                            withAnimation(.spring(response: 0.45, dampingFraction: 1.0)) {
                                panelManager.collapse()
                            }
                        }
                    }
                }
                .padding(.vertical, 8)
                .padding(.horizontal, inset)
            }
            .frame(maxHeight: 320)
        }
    }
}
