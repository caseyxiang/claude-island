import AppKit
import SwiftUI

/// Manages the floating pseudo-Dynamic Island window.
final class DynamicIslandWindowController {
    private var window: DynamicIslandPanel?
    let diState = DynamicIslandState()

    func show(sessionManager: SessionManager) {
        guard window == nil else { return }

        let contentView = DynamicIslandView(sessionManager: sessionManager, diState: diState)
        let win = DynamicIslandPanel(contentView: contentView)

        if let screen = NSScreen.main {
            let screenFrame = screen.frame
            let visibleFrame = screen.visibleFrame
            let x = screenFrame.midX - win.frame.width / 2
            let y = visibleFrame.maxY - 10
            win.setFrameOrigin(NSPoint(x: x, y: y))
        }

        win.orderFront(nil)
        self.window = win
    }

    func hide() {
        window?.orderOut(nil)
        window = nil
    }

    var isVisible: Bool {
        window?.isVisible ?? false
    }

    func showCompletion(session: AgentSession) {
        diState.showCompletion(session: session)
    }
}

// MARK: - Custom NSPanel

final class DynamicIslandPanel: NSPanel {
    init<Content: View>(contentView: Content) {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 340, height: 44),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        let hosting = NSHostingView(rootView:
            contentView
                .frame(maxWidth: 340, maxHeight: 200, alignment: .top)
                .fixedSize(horizontal: true, vertical: true)
        )

        self.contentView = hosting
        self.isOpaque = false
        self.backgroundColor = .clear
        self.level = .floating
        self.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        self.isMovableByWindowBackground = true
        self.hasShadow = false
        self.animationBehavior = .utilityWindow

        hosting.translatesAutoresizingMaskIntoConstraints = false
        if let cv = self.contentView {
            NSLayoutConstraint.activate([
                hosting.topAnchor.constraint(equalTo: cv.topAnchor),
                hosting.leadingAnchor.constraint(equalTo: cv.leadingAnchor),
            ])
        }
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}
