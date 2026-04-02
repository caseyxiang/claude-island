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
            return 680
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
            .onHover { isHovering in
                hovering = isHovering
                if isHovering && !panelManager.isExpanded {
                    // Mouse entered — expand
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                        panelManager.expand()
                    }
                } else if !isHovering && panelManager.isExpanded && !panelManager.isPinned {
                    // Mouse left and not pinned — collapse after short delay
                    Task { @MainActor in
                        try? await Task.sleep(for: .milliseconds(300))
                        if !hovering && !panelManager.isPinned {
                            withAnimation(.spring(response: 0.45, dampingFraction: 1.0)) {
                                panelManager.collapse()
                            }
                        }
                    }
                }
            }
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
            if newCount > 0 && !panelManager.isExpanded {
                // Auto-expand when a session needs attention
                withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                    panelManager.expand()
                }
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

    // MARK: - Collapsed

    @State private var currentWorkingIndex = 0
    @State private var scrollTimer: Timer?

    private var workingSessions: [AgentSession] {
        sessions(withStatus: .working)
    }

    private func sessions(withStatus status: SessionStatus) -> [AgentSession] {
        sessionManager.sessions.filter { $0.status == status }
    }

    private var collapsedContent: some View {
        Group {
            if !workingSessions.isEmpty {
                // Show working session title, scroll if multiple
                workingSessionTicker
            } else {
                // No working sessions — show summary
                idleSummary
            }
        }
        .padding(.horizontal, 14)
        .frame(height: 26)
        .frame(maxWidth: .infinity)
        .clipped()
        .background(Color.black.opacity(0.001))
        .onAppear { startScrollTimer() }
        .onDisappear { stopScrollTimer() }
    }

    @State private var marqueeOffset: CGFloat = 0
    @State private var marqueeTimer: Timer?

    private var workingSessionTicker: some View {
        let working = workingSessions
        let index = working.isEmpty ? 0 : currentWorkingIndex % working.count
        let session = working.isEmpty ? nil : working[index]

        return VStack {
            if let session {
                HStack(spacing: 6) {
                    PixelIconCompact(
                        status: .working,
                        hasUnreadCompletion: false
                    )

                    // Horizontal marquee for long titles
                    GeometryReader { geo in
                        (Text(session.workspaceName)
                            .foregroundColor(claudeOrange)
                        + Text(" · \(session.displayTitle)")
                            .foregroundColor(.white))
                            .font(.system(size: 11, weight: .medium, design: .monospaced))
                            .lineLimit(1)
                            .fixedSize()
                            .offset(x: marqueeOffset)
                            .onAppear { startMarquee(containerWidth: geo.size.width, session: session) }
                            .onChange(of: session.id) { _, _ in
                                startMarquee(containerWidth: geo.size.width, session: session)
                            }
                    }
                    .clipped()

                    if working.count > 1 {
                        Text("\(index + 1)/\(working.count)")
                            .font(.system(size: 9, weight: .medium, design: .rounded))
                            .foregroundStyle(.white.opacity(0.3))
                            .fixedSize()
                    }
                }
                .id("ticker-\(session.id)")
                .transition(.asymmetric(
                    insertion: .move(edge: .bottom).combined(with: .opacity),
                    removal: .move(edge: .top).combined(with: .opacity)
                ))
            }
        }
        .clipped()
    }

    private func startMarquee(containerWidth: CGFloat, session: AgentSession) {
        marqueeTimer?.invalidate()
        marqueeOffset = 0

        // Estimate text width (rough: 7pt per char for monospaced 11pt)
        let textWidth = CGFloat(session.displayTitle.count) * 7
        guard textWidth > containerWidth else { return } // no scroll needed

        let travel = textWidth - containerWidth + 20
        // Scroll right to left, pause, then reset
        marqueeTimer = Timer.scheduledTimer(withTimeInterval: 0.03, repeats: true) { [self] timer in
            withAnimation(.linear(duration: 0.03)) {
                marqueeOffset -= 0.5
            }
            if abs(marqueeOffset) > travel {
                timer.invalidate()
                // Pause then reset
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                    marqueeOffset = 0
                    startMarquee(containerWidth: containerWidth, session: session)
                }
            }
        }
    }

    @State private var breathe = false

    private var idleSummary: some View {
        HStack(spacing: 6) {
            PixelIconCompact(
                status: .idle,
                hasUnreadCompletion: false
            )

            if sessionManager.activeCount > 0 {
                Text("\(sessionManager.activeCount) sessions")
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.5))
            } else {
                Text("idle")
                    .font(.system(size: 11, design: .rounded))
                    .foregroundStyle(.white.opacity(0.4))
            }
        }
    }

    private func startScrollTimer() {
        breathe = true
        scrollTimer?.invalidate()
        guard workingSessions.count > 1 else { return }
        // Rotate to next working session every 5 seconds (vertical scroll up)
        scrollTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { _ in
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                currentWorkingIndex += 1
            }
        }
    }

    private func stopScrollTimer() {
        scrollTimer?.invalidate()
        scrollTimer = nil
    }

    // MARK: - Peek (notification bar)

    private var peekContent: some View {
        VStack(spacing: 0) {
            if let session = panelManager.alertSession {
                HStack(spacing: 6) {
                    PixelIconCompact(
                        status: session.status,
                        hasUnreadCompletion: !session.status.needsAttention
                    )

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
        .padding(.horizontal, 14)
        .frame(height: 36)
        .clipped()
    }

    // MARK: - Expanded (full session list)

    private var expandedContent: some View {
        let inset = topCR + 6

        return VStack(spacing: 0) {
            // Header
            HStack(spacing: 8) {
                Spacer()

                Text("\(sessionManager.activeCount) Active")
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.4))

                // Pin button
                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                        panelManager.isPinned.toggle()
                    }
                } label: {
                    Image(systemName: panelManager.isPinned ? "pin.fill" : "pin")
                        .font(.system(size: 10))
                        .foregroundStyle(panelManager.isPinned ? claudeOrange : .white.opacity(0.3))
                        .rotationEffect(.degrees(panelManager.isPinned ? 0 : 45))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, inset)
            .padding(.vertical, 6)
            .background(Color.black.opacity(0.001))
            .onTapGesture {
                if !panelManager.isPinned {
                    withAnimation(.spring(response: 0.45, dampingFraction: 1.0)) {
                        panelManager.collapse()
                    }
                }
            }

            Divider()
                .background(Color.white.opacity(0.06))
                .padding(.horizontal, inset)

            // Sessions
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 8) {
                    ForEach(sessionManager.sortedSessions) { session in
                        NotchSessionCard(
                            session: session,
                            onTap: {
                                panelManager.onJumpToTerminal?(session)
                                withAnimation(.spring(response: 0.45, dampingFraction: 1.0)) {
                                    panelManager.collapse()
                                }
                            },
                            onApprove: {
                                sessionManager.approvePermission(session: session, approved: true)
                            },
                            onDeny: {
                                sessionManager.approvePermission(session: session, approved: false)
                            }
                        )
                    }
                }
                .padding(.vertical, 8)
                .padding(.horizontal, inset)
            }
            .frame(maxHeight: 320)
        }
    }
}
