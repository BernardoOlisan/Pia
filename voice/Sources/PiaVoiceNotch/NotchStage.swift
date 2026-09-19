import AppKit
import Observation

/// The geometry the island is currently drawn with. It changes when the human moves to another screen,
/// plugs a monitor in, or changes the arrangement, and the views follow because it is observable.
@MainActor
@Observable
public final class IslandStage {
    public internal(set) var geometry: NotchGeometry
    /// The mockup can pin a style so the other one can be seen without the hardware.
    public var forcedStyle: IslandStyle?

    public init(geometry: NotchGeometry = .measure()) {
        self.geometry = geometry
    }

    func apply(_ measured: NotchGeometry) {
        geometry = forcedStyle.map { measured.forcing($0) } ?? measured
    }
}

/// Keeps the island on the screen the human is actually looking at, and on whichever Space is in front.
///
/// Three things move it: the pointer crossing to another display, the display arrangement changing, and
/// the human switching Space or leaving a full-screen app. macOS gives a notification for the last two;
/// the pointer has none, so it is read on a slow timer — `NSEvent.mouseLocation` costs nothing and needs
/// no permission.
@MainActor
final class ScreenFollower {
    private var tokens: [NSObjectProtocol] = []
    private var workspaceTokens: [NSObjectProtocol] = []
    private var timer: Timer?
    private var lastScreen: CGDirectDisplayID = 0
    private let onChange: (NotchGeometry, String) -> Void

    init(onChange: @escaping (NotchGeometry, String) -> Void) {
        self.onChange = onChange
    }

    func start() {
        guard timer == nil else { return }
        lastScreen = NotchGeometry.displayID(of: NotchGeometry.activeScreen())

        tokens.append(NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.fire("screen arrangement changed") }
        })

        let workspace = NSWorkspace.shared.notificationCenter
        workspaceTokens.append(workspace.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.fire("space changed") }
        })
        workspaceTokens.append(workspace.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.fire("app activated") }
        })

        // The pointer crossing displays has no notification of its own.
        let poll = Timer(timeInterval: 0.35, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                let id = NotchGeometry.displayID(of: NotchGeometry.activeScreen())
                guard id != self.lastScreen else { return }
                self.lastScreen = id
                self.fire("pointer moved to another screen")
            }
        }
        RunLoop.main.add(poll, forMode: .common)
        timer = poll
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        tokens.forEach { NotificationCenter.default.removeObserver($0) }
        workspaceTokens.forEach { NSWorkspace.shared.notificationCenter.removeObserver($0) }
        tokens = []
        workspaceTokens = []
    }

    private func fire(_ reason: String) {
        let measured = NotchGeometry.measure()
        lastScreen = measured.screenNumber
        onChange(measured, reason)
    }
}
