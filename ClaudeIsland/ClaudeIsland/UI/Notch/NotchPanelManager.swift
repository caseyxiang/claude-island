import AppKit
import SwiftUI
import OSLog

/// Manages the notch panel window, geometry, and state.
@Observable
final class NotchPanelManager {
    private let logger = Logger(subsystem: "com.claudeisland", category: "NotchPanel")
    private var panel: NotchPanel?

    // MARK: - State

    var isExpanded = false
    var isPinned = false
    var notchSize: CGSize = CGSize(width: 200, height: 32)
    var screenFrame: CGRect = .zero

    // Alert state
    var alertSession: AgentSession?
    var showingPeek = false

    // Jump callback — set by AppDelegate
    var onJumpToTerminal: ((AgentSession) -> Void)?

    // Current shape dimensions (set by NotchContentView for hitTest sync)
    var currentShapeWidth: CGFloat = 220
    var currentShapeHeight: CGFloat = 60

    // MARK: - Geometry

    /// The interactive rect for the notch area (collapsed state), in screen coordinates.
    var notchInteractiveRect: CGRect {
        let earWidth: CGFloat = 80
        let totalWidth = notchSize.width + earWidth * 2
        let x = screenFrame.midX - totalWidth / 2
        let y = screenFrame.maxY - notchSize.height - 8
        return CGRect(x: x, y: y, width: totalWidth, height: notchSize.height + 8)
    }

    /// The interactive rect when expanded, in screen coordinates.
    var expandedRect: CGRect {
        let width: CGFloat = 380
        let height: CGFloat = min(CGFloat(sessionCount) * 90 + 80, 400)
        let x = screenFrame.midX - width / 2
        let y = screenFrame.maxY - notchSize.height - height
        return CGRect(x: x, y: y, width: width, height: height + notchSize.height)
    }

    private var sessionCount: Int = 0

    func updateSessionCount(_ count: Int) {
        sessionCount = max(count, 1)
    }

    // MARK: - Show / Hide

    func show(sessionManager: SessionManager, diState: DynamicIslandState) {
        guard panel == nil, let screen = NSScreen.main else { return }

        screenFrame = screen.frame
        notchSize = screen.notchSize

        let notchPanel = NotchPanel(screen: screen)

        let contentView = NotchContentView(
            sessionManager: sessionManager,
            panelManager: self,
            diState: diState
        )

        // Wrap hosting view inside NotchHitTestView for click passthrough
        let hitTestView = NotchHitTestView()
        hitTestView.panelManager = self

        let hosting = NSHostingView(rootView: contentView)
        hosting.translatesAutoresizingMaskIntoConstraints = false
        hitTestView.addSubview(hosting)

        NSLayoutConstraint.activate([
            hosting.topAnchor.constraint(equalTo: hitTestView.topAnchor),
            hosting.bottomAnchor.constraint(equalTo: hitTestView.bottomAnchor),
            hosting.leadingAnchor.constraint(equalTo: hitTestView.leadingAnchor),
            hosting.trailingAnchor.constraint(equalTo: hitTestView.trailingAnchor),
        ])

        notchPanel.contentView = hitTestView

        notchPanel.orderFront(nil)
        self.panel = notchPanel
        logger.info("Notch panel shown")
    }

    func hide() {
        panel?.stopMonitors()
        panel?.orderOut(nil)
        panel = nil
    }

    // MARK: - Expand / Collapse

    func toggle() {
        isExpanded.toggle()
    }

    func expand() {
        isExpanded = true
    }

    func collapse() {
        isExpanded = false
    }

    // MARK: - Alert / Peek

    func showPeek(session: AgentSession) {
        alertSession = session
        showingPeek = true

        // Auto-collapse after 10 seconds
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(10))
            if showingPeek {
                showingPeek = false
                alertSession = nil
            }
        }
    }

    func showCompletion(session: AgentSession) {
        alertSession = session
        showingPeek = true

        Task { @MainActor in
            try? await Task.sleep(for: .seconds(10))
            if showingPeek, alertSession?.sessionId == session.sessionId {
                showingPeek = false
                alertSession = nil
            }
        }
    }

    func dismissPeek() {
        showingPeek = false
        alertSession = nil
    }
}
