import AppKit
import SwiftUI

/// Full-width panel covering the top of the screen.
final class NotchPanel: NSPanel {
    init(screen: NSScreen) {
        let windowHeight: CGFloat = 500
        let frame = NSRect(
            x: screen.frame.origin.x,
            y: screen.frame.maxY - windowHeight,
            width: screen.frame.width,
            height: windowHeight
        )
        super.init(
            contentRect: frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        isFloatingPanel = true
        level = .mainMenu + 3
        collectionBehavior = [.fullScreenAuxiliary, .stationary, .canJoinAllSpaces, .ignoresCycle]
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        isMovable = false
        animationBehavior = .none
        acceptsMouseMovedEvents = true
        ignoresMouseEvents = true  // Start ignoring; global monitor toggles this
        startGlobalMouseMonitor()
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    private var globalMonitor: Any?
    private var localMonitor: Any?

    private func startGlobalMouseMonitor() {
        // Global monitor tracks mouse across ALL apps
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved, .leftMouseDown, .leftMouseDragged]) { [weak self] event in
            self?.updateIgnoresMouseEvents()
        }
        // Local monitor tracks mouse when our app is active
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged]) { [weak self] event in
            self?.updateIgnoresMouseEvents()
            return event
        }
    }

    func stopMonitors() {
        if let g = globalMonitor { NSEvent.removeMonitor(g) }
        if let l = localMonitor { NSEvent.removeMonitor(l) }
        globalMonitor = nil
        localMonitor = nil
    }

    private func updateIgnoresMouseEvents() {
        guard let hitView = contentView as? NotchHitTestView,
              let manager = hitView.panelManager else { return }

        let mouse = NSEvent.mouseLocation
        let centerX = manager.screenFrame.midX
        let screenTop = manager.screenFrame.maxY
        let w = manager.currentShapeWidth + 10
        let h = manager.currentShapeHeight + 5

        let inside = mouse.x >= centerX - w / 2
            && mouse.x <= centerX + w / 2
            && mouse.y >= screenTop - h

        if ignoresMouseEvents == inside {
            ignoresMouseEvents = !inside
        }
    }
}

/// Wrapper NSView that controls click passthrough.
/// Only allows clicks within the notch island's visible area.
final class NotchHitTestView: NSView {
    weak var panelManager: NotchPanelManager?

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard let window, let manager = panelManager else { return nil }

        let windowPoint = convert(point, to: nil)
        let screenPoint = window.convertPoint(toScreen: windowPoint)

        let centerX = manager.screenFrame.midX
        let screenTop = manager.screenFrame.maxY
        let w = manager.currentShapeWidth + 10
        let h = manager.currentShapeHeight + 5

        let left = centerX - w / 2
        let right = centerX + w / 2
        let bottom = screenTop - h

        // Outside the island area — pass through
        guard screenPoint.x >= left && screenPoint.x <= right && screenPoint.y >= bottom else {
            return nil
        }

        // Inside — let SwiftUI handle it
        return super.hitTest(point)
    }
}
