import AppKit

/// Sizes measured from the screen, not assumed: notch width and height differ per Mac.
struct NotchGeometry {
    let notchWidth: CGFloat
    let notchHeight: CGFloat
    let menuBarHeight: CGFloat
    let screenFrame: CGRect

    static let meterWidth: CGFloat = 22
    static let meterHeight: CGFloat = 16
    static let inset: CGFloat = 7
    /// Room for the dot and "$0.00".
    static let leftContentWidth: CGFloat = 48
    /// How far the island grows per side and downward at full voice loudness.
    static let lift = CGSize(width: 10, height: 8)

    static func current() -> NotchGeometry {
        let screen = NSScreen.screens.first(where: { $0.safeAreaInsets.top > 0 }) ?? NSScreen.main ?? NSScreen.screens[0]
        let hasNotch = screen.safeAreaInsets.top > 0
        var width: CGFloat = 0
        if hasNotch, let left = screen.auxiliaryTopLeftArea, let right = screen.auxiliaryTopRightArea {
            width = max(0, right.minX - left.maxX)
        }
        let menuBar = max(screen.frame.maxY - screen.visibleFrame.maxY, screen.safeAreaInsets.top)
        return NotchGeometry(notchWidth: width, notchHeight: hasNotch ? screen.safeAreaInsets.top : 0,
                             menuBarHeight: menuBar, screenFrame: screen.frame)
    }

    var inverseRadius: CGFloat { notchHeight > 0 ? notchHeight * 0.35 : 0 }

    var wingWidth: CGFloat { Self.leftContentWidth + 2 * Self.inset }

    /// Wider than the notch by a wing each side; as tall as the notch or menu bar, whichever is taller.
    var restingSize: CGSize {
        let height = notchHeight > 0 ? max(notchHeight, menuBarHeight) : 30
        return CGSize(width: notchWidth + 2 * wingWidth + 2 * inverseRadius, height: height)
    }

    /// The transparent window: big enough for the island at its largest pulse, and never moves.
    var stageFrame: CGRect {
        let w = restingSize.width + 2 * Self.lift.width + 4
        let h = restingSize.height + Self.lift.height + 4
        return CGRect(x: (screenFrame.midX - w / 2).rounded(), y: screenFrame.maxY - h, width: w, height: h)
    }
}
