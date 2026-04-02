import AppKit

extension NSScreen {
    /// Whether this screen has a physical notch (camera housing).
    var hasNotch: Bool {
        if #available(macOS 12.0, *) {
            return safeAreaInsets.top > 0
        }
        return false
    }

    /// The computed size of the notch area.
    var notchSize: CGSize {
        guard hasNotch else {
            // Fallback for screens without notch — simulate a small pill
            return CGSize(width: 200, height: 32)
        }
        if #available(macOS 12.0, *) {
            let fullWidth = frame.width
            let leftPadding = auxiliaryTopLeftArea?.width ?? 0
            let rightPadding = auxiliaryTopRightArea?.width ?? 0
            let notchWidth = fullWidth - leftPadding - rightPadding + 4
            let notchHeight = safeAreaInsets.top + 2
            return CGSize(width: notchWidth, height: notchHeight)
        }
        return CGSize(width: 200, height: 32)
    }

    /// The rect of the notch area in screen coordinates.
    var notchRect: CGRect {
        let size = notchSize
        let x = frame.midX - size.width / 2
        let y = frame.maxY - size.height
        return CGRect(x: x, y: y, width: size.width, height: size.height)
    }
}
