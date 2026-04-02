import SwiftUI

/// Notch-shaped clip path with inward-curving top corners (matching hardware notch)
/// and outward-curving bottom corners. Animatable between collapsed and expanded states.
///
/// Collapsed (matches hardware notch):
///   ╭──────────────────────╮   ← inward top corners
///   │                      │
///   │                      │
///   ╰──╮                ╭──╯   ← outward bottom corners
///      ╰────────────────╯
///
struct NotchShape: Shape {
    var topCornerRadius: CGFloat
    var bottomCornerRadius: CGFloat

    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(topCornerRadius, bottomCornerRadius) }
        set {
            topCornerRadius = newValue.first
            bottomCornerRadius = newValue.second
        }
    }

    func path(in rect: CGRect) -> Path {
        let tcr = topCornerRadius
        let bcr = bottomCornerRadius

        var path = Path()

        // Start at top-left corner
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))

        // Top-left inward curve (concave, mimics notch hardware edge)
        path.addQuadCurve(
            to: CGPoint(x: rect.minX + tcr, y: rect.minY + tcr),
            control: CGPoint(x: rect.minX + tcr, y: rect.minY)
        )

        // Left edge down
        path.addLine(to: CGPoint(x: rect.minX + tcr, y: rect.maxY - bcr))

        // Bottom-left outward curve (convex)
        path.addQuadCurve(
            to: CGPoint(x: rect.minX + tcr + bcr, y: rect.maxY),
            control: CGPoint(x: rect.minX + tcr, y: rect.maxY)
        )

        // Bottom edge
        path.addLine(to: CGPoint(x: rect.maxX - tcr - bcr, y: rect.maxY))

        // Bottom-right outward curve (convex)
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX - tcr, y: rect.maxY - bcr),
            control: CGPoint(x: rect.maxX - tcr, y: rect.maxY)
        )

        // Right edge up
        path.addLine(to: CGPoint(x: rect.maxX - tcr, y: rect.minY + tcr))

        // Top-right inward curve (concave, mimics notch hardware edge)
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX, y: rect.minY),
            control: CGPoint(x: rect.maxX - tcr, y: rect.minY)
        )

        // Top edge back to start
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY))

        return path
    }
}
