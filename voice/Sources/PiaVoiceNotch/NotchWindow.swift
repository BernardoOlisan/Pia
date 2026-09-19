import AppKit
import SwiftUI

/// A borderless, non-activating panel above the menu bar: clicking it never takes focus from your editor.
final class NotchPanel: NSPanel {
    init(content: NSView) {
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        // canJoinAllSpaces: every Space, including the ones made by Mission Control.
        // fullScreenAuxiliary: also over an app that is full screen.
        // stationary: Mission Control doesn't shuffle it around. ignoresCycle: not in ⌘-tab / window cycling.
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        isMovable = false
        isMovableByWindowBackground = false
        hidesOnDeactivate = false
        isFloatingPanel = true
        becomesKeyOnlyIfNeeded = true
        isReleasedWhenClosed = false
        // After isFloatingPanel: its setter resets the level to .floating, below the menu bar.
        level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.statusWindow)) + 1)
        contentView = content
        appearance = NSAppearance(named: .darkAqua)
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// Shows the island: the whole time for the intent, only while dictating for transcribe.
///
/// It follows the human across Spaces and across screens. `canJoinAllSpaces` alone is not enough in
/// practice — a panel that was ordered front on one Space can stop being drawn on another after a
/// full-screen app or a display change — so every Space change re-orders it and re-measures the screen.
@MainActor
public final class NotchWindow {
    private let panel: NotchPanel
    private let stage: IslandStage
    private let maxSideWidth: CGFloat
    private var follower: ScreenFollower?
    private var shown = false
    /// What was last reported, so a diagnostic only appears when something actually moved.
    private var reported: NotchGeometry?
    /// Set by the mockup to print what the window is doing.
    public var diagnostics: ((String) -> Void)?

    public convenience init(model: NotchModel, stage: IslandStage? = nil) {
        let stage = stage ?? IslandStage()
        self.init(stage: stage, maxSideWidth: NotchView.maxSideWidth) { NotchView(model: model, stage: stage) }
    }

    public convenience init(dictation model: DictationModel, stage: IslandStage? = nil) {
        let stage = stage ?? IslandStage()
        self.init(stage: stage, maxSideWidth: DictationView.maxSideWidth) { DictationView(model: model, stage: stage) }
    }

    private init<Root: View>(stage: IslandStage, maxSideWidth: CGFloat, root: () -> Root) {
        self.stage = stage
        self.maxSideWidth = maxSideWidth
        let host = NSHostingView(rootView: root())
        host.safeAreaRegions = []
        panel = NotchPanel(content: host)
        panel.setFrame(stage.geometry.stageFrame(maxSideWidth: maxSideWidth), display: false)
    }

    public func show() {
        panel.orderFrontRegardless()
        guard !shown else { return }
        shown = true
        relayout(NotchGeometry.measure(), reason: "shown")

        let follower = ScreenFollower { [weak self] measured, reason in
            self?.relayout(measured, reason: reason)
        }
        follower.start()
        self.follower = follower
    }

    public func hide() {
        shown = false
        follower?.stop()
        follower = nil
        panel.orderOut(nil)
    }

    /// The mockup pins a style; the real island always follows the hardware.
    public func force(style: IslandStyle?) {
        stage.forcedStyle = style
        relayout(NotchGeometry.measure(), reason: "style forced")
    }

    private func relayout(_ measured: NotchGeometry, reason: String) {
        guard shown else { return }
        stage.apply(measured)
        panel.setFrame(stage.geometry.stageFrame(maxSideWidth: maxSideWidth), display: true)
        // A Space change can leave the panel behind even with canJoinAllSpaces; asking again is free.
        panel.orderFrontRegardless()
        // Switching apps fires this constantly. Only say something when the island really moved,
        // or was not where it should have been — that is the only line worth keeping in a log.
        let moved = reported != stage.geometry
        let lost = !panel.isOnActiveSpace || !panel.isVisible
        guard moved || lost else { return }
        reported = stage.geometry
        diagnostics?("\(reason) · screen \(stage.geometry.screenNumber) "
            + "\(Int(stage.geometry.screenFrame.width))×\(Int(stage.geometry.screenFrame.height)) "
            + "· style \(stage.geometry.style == .notch ? "notch" : "capsule") "
            + "· onActiveSpace \(panel.isOnActiveSpace) · visible \(panel.isVisible)")
    }
}
