import SwiftUI
import AppKit

// MARK: - Pixel Icon Image Loader

/// Loads pixel sprites from the bundle. Caches all loaded images.
enum PixelIconLoader {
    private static var cache: [String: NSImage] = [:]

    static func image(named name: String) -> NSImage? {
        if let cached = cache[name] { return cached }

        // Try asset catalog via Bundle.module
        if let img = Bundle.module.image(forResource: name) {
            cache[name] = img
            return img
        }

        // Fallback: direct file lookup in xcassets bundle structure
        for ext in ["png", "jpeg"] {
            let imageset = "\(name).imageset"
            let filename = "\(name).\(ext)"
            if let url = Bundle.module.url(
                forResource: filename,
                withExtension: nil,
                subdirectory: "Assets.xcassets/\(imageset)"
            ), let img = NSImage(contentsOf: url) {
                cache[name] = img
                return img
            }
        }

        return nil
    }

    /// Preload all sprite frames into cache
    static func preloadFrames() {
        for i in 0...3 {
            _ = image(named: "sprite-run-\(i)")
            _ = image(named: "sprite-completed-\(i)")
        }
        _ = image(named: "sprite-static")
        _ = image(named: "sprite-look-0")
        _ = image(named: "sprite-look-1")
    }
}

// MARK: - Status Style

private struct StatusStyle {
    let tint: Color?       // nil = no tint, show original colors
    let brightness: Double  // 0 = no change
    let symbol: String?
    let symbolColor: Color

    static func from(session: AgentSession) -> StatusStyle {
        if session.hasUnreadCompletion {
            return StatusStyle(tint: nil, brightness: 0, symbol: nil, symbolColor: .clear)
        }
        switch session.status {
        case .working:
            return StatusStyle(tint: nil, brightness: 0, symbol: nil, symbolColor: .clear)
        case .idle, .done:
            return StatusStyle(tint: nil, brightness: 0, symbol: "z", symbolColor: .white.opacity(0.5))
        case .waitingPermission, .waitingAnswer:
            return StatusStyle(tint: nil, brightness: 0, symbol: nil, symbolColor: .clear)
        }
    }

    static func from(status: SessionStatus, hasUnread: Bool) -> StatusStyle {
        if hasUnread {
            return StatusStyle(tint: nil, brightness: 0, symbol: nil, symbolColor: .clear)
        }
        switch status {
        case .working:
            return StatusStyle(tint: nil, brightness: 0, symbol: nil, symbolColor: .clear)
        case .idle, .done:
            return StatusStyle(tint: nil, brightness: 0, symbol: nil, symbolColor: .clear)
        case .waitingPermission, .waitingAnswer:
            return StatusStyle(tint: nil, brightness: 0, symbol: nil, symbolColor: .clear)
        }
    }
}

// MARK: - Sprite Frame Animator

/// Drives frame-by-frame sprite animation using a Timer.
@Observable
final class SpriteAnimator {
    var currentFrame: Int = 0
    private var timer: Timer?
    private let frameNames: [String]
    private let fps: Double

    init(frameNames: [String], fps: Double = 8) {
        self.frameNames = frameNames
        self.fps = fps
    }

    var currentImageName: String {
        frameNames.isEmpty ? "kenney-robot" : frameNames[currentFrame % frameNames.count]
    }

    func start() {
        guard timer == nil, frameNames.count > 1 else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 1.0 / fps, repeats: true) { [weak self] _ in
            guard let self else { return }
            self.currentFrame = (self.currentFrame + 1) % self.frameNames.count
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        currentFrame = 0
    }

    deinit {
        timer?.invalidate()
    }
}

// MARK: - PixelIconView (expanded panel)

struct PixelIconView: View {
    let session: AgentSession
    let size: CGFloat

    @State private var runAnimator = SpriteAnimator(
        frameNames: ["sprite-run-0", "sprite-run-1", "sprite-run-2", "sprite-run-3"],
        fps: 8
    )
    @State private var completedAnimator = SpriteAnimator(
        frameNames: ["sprite-completed-0", "sprite-completed-1", "sprite-completed-2", "sprite-completed-3"],
        fps: 4
    )
    @State private var lookAnimator = SpriteAnimator(
        frameNames: ["sprite-look-0", "sprite-look-1"],
        fps: 1.5
    )
    @State private var phase1 = false
    @State private var phase2 = false

    private var style: StatusStyle {
        StatusStyle.from(session: session)
    }

    private var glowColor: Color {
        if session.status == .working || session.hasUnreadCompletion {
            return .orange.opacity(0.7)
        }
        if session.status == .idle || session.status == .done {
            return .white.opacity(0.6)
        }
        if session.status.needsAttention {
            return .orange.opacity(0.7)
        }
        return .clear
    }

    private var currentImageName: String {
        if session.status == .working {
            return runAnimator.currentImageName
        }
        if session.hasUnreadCompletion {
            return completedAnimator.currentImageName
        }
        if session.status.needsAttention {
            return lookAnimator.currentImageName
        }
        return "sprite-static"
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            spriteImage(name: currentImageName, size: size)
                .modifier(TintModifier(tint: style.tint, brightness: style.brightness))
                .shadow(color: glowColor, radius: glowColor == .clear ? 0 : 6)

            if let symbol = style.symbol {
                Text(symbol)
                    .font(.system(size: size * 0.35, weight: .black, design: .rounded))
                    .foregroundStyle(style.symbolColor)
                    .shadow(color: .black, radius: 1)
                    .offset(x: 2, y: -2)
            }
        }
        .frame(width: size, height: size)
        .modifier(StatusAnimationModifier(
            session: session,
            phase1: $phase1,
            phase2: $phase2
        ))
        .onChange(of: session.status) { _, newStatus in
            updateAnimators(for: newStatus, hasUnread: session.hasUnreadCompletion)
        }
        .onChange(of: session.hasUnreadCompletion) { _, hasUnread in
            updateAnimators(for: session.status, hasUnread: hasUnread)
        }
        .onAppear {
            PixelIconLoader.preloadFrames()
            updateAnimators(for: session.status, hasUnread: session.hasUnreadCompletion)
        }
        .onDisappear {
            runAnimator.stop()
            completedAnimator.stop()
            lookAnimator.stop()
        }
    }

    private func updateAnimators(for status: SessionStatus, hasUnread: Bool) {
        if status == .working {
            runAnimator.start()
            completedAnimator.stop()
            lookAnimator.stop()
        } else if hasUnread {
            runAnimator.stop()
            completedAnimator.start()
            lookAnimator.stop()
        } else if status.needsAttention {
            runAnimator.stop()
            completedAnimator.stop()
            lookAnimator.start()
        } else {
            runAnimator.stop()
            completedAnimator.stop()
            lookAnimator.stop()
        }
    }
}

// MARK: - Compact Variant (collapsed notch bar)

struct PixelIconCompact: View {
    let status: SessionStatus
    let hasUnreadCompletion: Bool

    @State private var runAnimator = SpriteAnimator(
        frameNames: ["sprite-run-0", "sprite-run-1", "sprite-run-2", "sprite-run-3"],
        fps: 8
    )
    @State private var completedAnimator = SpriteAnimator(
        frameNames: ["sprite-completed-0", "sprite-completed-1", "sprite-completed-2", "sprite-completed-3"],
        fps: 4
    )
    @State private var lookAnimator = SpriteAnimator(
        frameNames: ["sprite-look-0", "sprite-look-1"],
        fps: 1.5
    )
    @State private var phase1 = false
    @State private var phase2 = false

    private var style: StatusStyle {
        StatusStyle.from(status: status, hasUnread: hasUnreadCompletion)
    }

    private var glowColor: Color {
        if status == .working || hasUnreadCompletion {
            return .orange.opacity(0.7)
        }
        if status == .idle || status == .done {
            return .white.opacity(0.6)
        }
        if status.needsAttention {
            return .orange.opacity(0.7)
        }
        return .clear
    }

    private var currentImageName: String {
        if status == .working {
            return runAnimator.currentImageName
        }
        if hasUnreadCompletion {
            return completedAnimator.currentImageName
        }
        if status.needsAttention {
            return lookAnimator.currentImageName
        }
        return "sprite-static"
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            spriteImage(name: currentImageName, size: 18)
                .modifier(TintModifier(tint: style.tint, brightness: style.brightness))
                .shadow(color: glowColor, radius: glowColor == .clear ? 0 : 4)

            if let symbol = style.symbol {
                Text(symbol)
                    .font(.system(size: 7, weight: .black, design: .rounded))
                    .foregroundStyle(style.symbolColor)
                    .shadow(color: .black, radius: 1)
                    .offset(x: 1, y: -1)
            }
        }
        .frame(width: 18, height: 18)
        .modifier(CompactAnimationModifier(
            status: status,
            hasUnreadCompletion: hasUnreadCompletion,
            phase1: $phase1,
            phase2: $phase2
        ))
        .onAppear {
            if status == .working { runAnimator.start() }
            else if hasUnreadCompletion { completedAnimator.start() }
            else if status.needsAttention { lookAnimator.start() }
        }
        .onDisappear { runAnimator.stop(); completedAnimator.stop(); lookAnimator.stop() }
        .onChange(of: status) { _, newStatus in
            runAnimator.stop(); completedAnimator.stop(); lookAnimator.stop()
            if newStatus == .working { runAnimator.start() }
            else if newStatus.needsAttention { lookAnimator.start() }
        }
    }
}

// MARK: - Shared Sprite Image

private func spriteImage(name: String, size: CGFloat) -> some View {
    Group {
        if let nsImage = PixelIconLoader.image(named: name) {
            Image(nsImage: nsImage)
                .resizable()
                .interpolation(.none)
                .aspectRatio(contentMode: .fit)
        } else {
            Image(systemName: "cpu")
                .font(.system(size: size * 0.6))
                .foregroundStyle(.white)
        }
    }
    .frame(width: size, height: size)
}

// MARK: - Tint Modifier

/// Applies color tint only when specified; otherwise shows original sprite colors.
private struct TintModifier: ViewModifier {
    let tint: Color?
    let brightness: Double

    func body(content: Content) -> some View {
        if let tint {
            content
                .colorMultiply(tint)
                .brightness(brightness)
        } else {
            content
        }
    }
}

// MARK: - Animation Modifiers

private struct StatusAnimationModifier: ViewModifier {
    let session: AgentSession
    @Binding var phase1: Bool
    @Binding var phase2: Bool

    func body(content: Content) -> some View {
        if session.hasUnreadCompletion {
            // COMPLETED — frame animation only, no extra effects
            content
        } else {
            switch session.status {
            case .working:
                // WORKING — frame animation only, no extra effects
                content

            case .idle, .done:
                // IDLE — slow gentle float
                content
                    .offset(y: phase1 ? -1 : 1)
                    .opacity(phase1 ? 0.85 : 0.75)
                    .onAppear {
                        withAnimation(.easeInOut(duration: 2.5).repeatForever(autoreverses: true)) {
                            phase1 = true
                        }
                    }

            case .waitingPermission, .waitingAnswer:
                // NEEDS INPUT — frame animation (head turn) only
                content
            }
        }
    }
}

private struct CompactAnimationModifier: ViewModifier {
    let status: SessionStatus
    let hasUnreadCompletion: Bool
    @Binding var phase1: Bool
    @Binding var phase2: Bool

    func body(content: Content) -> some View {
        if hasUnreadCompletion {
            // COMPLETED — frame animation only
            content
        } else if status == .working {
            // WORKING — frame animation only
            content
        } else if status.needsAttention {
            // NEEDS INPUT — frame animation (head turn) only
            content
        } else {
            content
                .offset(y: phase1 ? -0.5 : 0.5)
                .opacity(0.8)
                .onAppear {
                    withAnimation(.easeInOut(duration: 2.0).repeatForever(autoreverses: true)) {
                        phase1 = true
                    }
                }
        }
    }
}
