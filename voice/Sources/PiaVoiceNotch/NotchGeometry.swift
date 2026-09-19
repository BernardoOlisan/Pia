import AppKit

/// Where the island is drawn, and how it is shaped there.
///
/// - `notch`: the Mac has a notch. The island melts into it: flat top, concave joins, convex bottom.
/// - `capsule`: no notch (an external monitor). Nothing to melt into, so it floats as a full pill
///   in the menu bar, like the Dynamic Island on a phone.
public enum IslandStyle: Equatable, Sendable {
    case notch
    case capsule
}

/// Sizes measured from one screen, never assumed: notch width, notch height and menu bar differ per Mac,
/// and an external monitor has no notch at all.
public struct NotchGeometry: Equatable, Sendable {
    public let style: IslandStyle
    /// 0 in `capsule` style.
    public let notchWidth: CGFloat
    /// 0 in `capsule` style.
    public let notchHeight: CGFloat
    public let menuBarHeight: CGFloat
    public let screenFrame: CGRect
    /// Which screen this was measured on, so a change of screen is detectable.
    public let screenNumber: CGDirectDisplayID

    /// How far the island grows per side and downward at full loudness (the intent island only).
    public static let lift = CGSize(width: 10, height: 8)
    /// Slack around the island inside its transparent window.
    public static let slack: CGFloat = 8

    // MARK: Measuring

    /// The geometry of one screen. `nil` falls back to the screen the pointer is on.
    public static func measure(_ screen: NSScreen? = nil) -> NotchGeometry {
        let screen = screen ?? activeScreen()
        let hasNotch = screen.safeAreaInsets.top > 0
        var notch: CGFloat = 0
        if hasNotch, let left = screen.auxiliaryTopLeftArea, let right = screen.auxiliaryTopRightArea {
            notch = max(0, right.minX - left.maxX)
        }
        let menuBar = max(screen.frame.maxY - screen.visibleFrame.maxY, screen.safeAreaInsets.top)
        return NotchGeometry(
            style: notch > 0 ? .notch : .capsule,
            notchWidth: notch > 0 ? notch : 0,
            notchHeight: notch > 0 ? screen.safeAreaInsets.top : 0,
            menuBarHeight: menuBar,
            screenFrame: screen.frame,
            screenNumber: displayID(of: screen))
    }

    /// The screen the pointer is on — that is the screen the human is looking at. Falls back to the main one.
    public static func activeScreen() -> NSScreen {
        let mouse = NSEvent.mouseLocation
        return NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) }
            ?? NSScreen.main
            ?? NSScreen.screens.first!
    }

    public static func displayID(of screen: NSScreen) -> CGDirectDisplayID {
        (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0
    }

    /// The same geometry forced into the other style, for the mockup: an external monitor can be
    /// previewed on the built-in screen and the other way round.
    public func forcing(_ style: IslandStyle) -> NotchGeometry {
        guard style != self.style else { return self }
        switch style {
        case .capsule:
            return NotchGeometry(style: .capsule, notchWidth: 0, notchHeight: 0, menuBarHeight: menuBarHeight,
                                 screenFrame: screenFrame, screenNumber: screenNumber)
        case .notch:
            // A believable notch for a screen that has none: the 14"/16" proportions.
            let height = max(menuBarHeight, 32)
            return NotchGeometry(style: .notch, notchWidth: 200, notchHeight: height, menuBarHeight: menuBarHeight,
                                 screenFrame: screenFrame, screenNumber: screenNumber)
        }
    }

    // MARK: Shape

    /// The island's height at rest.
    public var barHeight: CGFloat {
        switch style {
        case .notch: return max(notchHeight, menuBarHeight)
        case .capsule: return 26
        }
    }

    /// How far below the top edge the island floats. A notch island is flush; a capsule breathes.
    public var topGap: CGFloat {
        switch style {
        case .notch: return 0
        case .capsule: return max(2, (menuBarHeight - barHeight) / 2)
        }
    }

    /// The concave joins that melt the island into the menu bar. Zero for a capsule.
    public var inverseRadius: CGFloat { style == .notch ? notchHeight * 0.35 : 0 }

    /// The gap the content leaves in the middle: the real notch, or breathing room in a capsule.
    public var middleGap: CGFloat { style == .notch ? notchWidth : 44 }

    /// The waveform is a strip inside the island, not the whole height of it — that is what makes it
    /// read as Voice Memos rather than as a bar chart wedged into the menu bar.
    public var waveHeight: CGFloat { min(15, barHeight * 0.42) }

    /// Padding at each end of the island's content, measured from the island's frame.
    ///
    /// The concave joins eat into the frame, so content has to clear them as well as its own inset —
    /// otherwise the waveform is drawn on top of the curve that melts the island into the menu bar.
    public var contentInset: CGFloat { (style == .notch ? 9 : 11) + inverseRadius }

    /// The width the island collapses to when hidden — the notch itself, or a small pill.
    public var foldedWidth: CGFloat { style == .notch ? notchWidth + 2 * inverseRadius : 46 }

    // MARK: The window

    /// The transparent window: wide enough for the island at its widest, and it never moves while shown.
    ///
    /// The island is centred on the **notch**, not on itself, so a wider left side grows leftwards.
    /// The window therefore has to hold the widest side twice.
    public func stageFrame(maxSideWidth: CGFloat) -> CGRect {
        let width = middleGap + 2 * maxSideWidth + 2 * (inverseRadius + Self.lift.width + Self.slack)
        let height = barHeight + topGap + Self.lift.height + Self.slack
        return CGRect(x: (screenFrame.midX - width / 2).rounded(),
                      y: screenFrame.maxY - height,
                      width: width.rounded(),
                      height: height.rounded())
    }
}
