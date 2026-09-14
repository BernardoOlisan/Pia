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

/// Shows the notch island: the whole time for the intent, only while dictating for transcribe.
@MainActor
public final class NotchWindow {
    private let panel: NotchPanel
    private let leftContentWidth: CGFloat
    private var observer: Any?

    public convenience init(model: NotchModel) {
        let geometry = NotchGeometry.current()
        self.init(root: NotchView(model: model, geometry: geometry), leftContentWidth: geometry.leftContentWidth)
    }

    public convenience init(dictation model: DictationModel) {
        let geometry = NotchGeometry.current(leftContentWidth: DictationView.leftContentWidth)
        self.init(root: DictationView(model: model, geometry: geometry), leftContentWidth: geometry.leftContentWidth)
    }

    private init(root: some View, leftContentWidth: CGFloat) {
        self.leftContentWidth = leftContentWidth
        let host = NSHostingView(rootView: root)
        host.safeAreaRegions = []
        panel = NotchPanel(content: host)
        panel.setFrame(NotchGeometry.current(leftContentWidth: leftContentWidth).stageFrame, display: true)
    }

    public func show() {
        panel.orderFrontRegardless()
        guard observer == nil else { return }
        observer = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.panel.setFrame(NotchGeometry.current(leftContentWidth: self.leftContentWidth).stageFrame, display: true)
            }
        }
    }

    public func hide() {
        if let observer { NotificationCenter.default.removeObserver(observer) }
        observer = nil
        panel.orderOut(nil)
    }
}
