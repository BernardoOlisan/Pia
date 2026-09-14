import AppKit
import SwiftUI

/// A borderless, non-activating panel above the menu bar: clicking it never takes focus from your editor.
final class NotchPanel: NSPanel {
    init(content: NSView) {
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        isMovable = false
        hidesOnDeactivate = false
        isFloatingPanel = true
        becomesKeyOnlyIfNeeded = true
        // After isFloatingPanel: its setter resets the level to .floating, below the menu bar.
        level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.statusWindow)) + 1)
        contentView = content
        appearance = NSAppearance(named: .darkAqua)
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// Shows the notch island for as long as pia-voice runs.
@MainActor
public final class NotchWindow {
    private let panel: NotchPanel
    private var observer: Any?

    public init(model: NotchModel) {
        let geometry = NotchGeometry.current()
        let host = NSHostingView(rootView: NotchView(model: model, geometry: geometry))
        host.safeAreaRegions = []
        panel = NotchPanel(content: host)
        panel.setFrame(geometry.stageFrame, display: true)
    }

    public func show() {
        panel.orderFrontRegardless()
        observer = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.panel.setFrame(NotchGeometry.current().stageFrame, display: true) }
        }
    }

    public func hide() {
        if let observer { NotificationCenter.default.removeObserver(observer) }
        panel.orderOut(nil)
    }
}
