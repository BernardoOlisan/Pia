import AppKit
import Foundation
import UserNotifications

/// A native macOS notification: the owl as the app icon, and the owl's sound for each kind.
///
///   PIA notify --kind ready|done|stalled|permission --title "…" [--subtitle "…"] [--body "…"] [--thread <id>]
///
/// It has to run from inside PIA.app: macOS only lets a bundled app with an identifier post
/// notifications, and it shows that bundle's icon. The first time, macOS asks whether PIA may.
enum Notify {
    static let kinds = ["ready", "done", "stalled", "permission"]

    final class Delegate: NSObject, UNUserNotificationCenterDelegate {
        func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                    withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
            completionHandler([.banner, .list, .sound])
        }
    }

    static func run(_ arguments: [String]) -> Int32 {
        var args = arguments
        var kind = "done", title = "PIA", subtitle: String?, body = "", thread = "pia"
        while !args.isEmpty {
            let flag = args.removeFirst()
            guard !args.isEmpty else { return fail("missing value for \(flag)") }
            let value = args.removeFirst()
            switch flag {
            case "--kind": kind = value
            case "--title": title = value
            case "--subtitle": subtitle = value
            case "--body": body = value
            case "--thread": thread = value
            default: return fail("unknown option \(flag)")
            }
        }
        guard kinds.contains(kind) else { return fail("kind must be one of \(kinds.joined(separator: ", "))") }
        return post(kind: kind, title: title, subtitle: subtitle, body: body, thread: thread)
    }

    static func post(kind: String, title: String, subtitle: String? = nil, body: String, thread: String = "pia") -> Int32 {
        guard Bundle.main.bundleIdentifier != nil else {
            return fail("run this from PIA.app (scripts/pia-app.sh path), not the bare binary")
        }
        let center = UNUserNotificationCenter.current()
        let delegate = Delegate()
        center.delegate = delegate
        let done = DispatchSemaphore(value: 0)
        var status: Int32 = 0
        center.requestAuthorization(options: [.alert, .sound]) { granted, error in
            guard granted else {
                status = 3
                FileHandle.standardError.write("PIA: notifications are not allowed (System Settings → Notifications → PIA)\(error.map { ": \($0)" } ?? "")\n".data(using: .utf8)!)
                done.signal()
                return
            }
            let content = UNMutableNotificationContent()
            content.title = title
            if let subtitle, !subtitle.isEmpty { content.subtitle = subtitle }
            content.body = body
            content.threadIdentifier = thread
            // No system sound: macOS ignored the bundled one and played its default. PIA plays the
            // owl itself below, so the sound is always the one the human chose.
            content.sound = nil
            let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
            center.add(request) { error in
                if let error {
                    status = 4
                    FileHandle.standardError.write("PIA: \(error)\n".data(using: .utf8)!)
                }
                done.signal()
            }
        }
        // The first time, macOS waits for the human to answer its permission prompt.
        let deadline = Date().addingTimeInterval(120)
        while done.wait(timeout: .now()) == .timedOut {
            if Date() > deadline { return fail("timed out waiting for macOS") }
            RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        }
        if status == 0 { playOwl(kind) }
        withExtendedLifetime(delegate) {}
        return status
    }

    /// The owl's sound for this kind, from the bundle, played to the end.
    static func playOwl(_ kind: String) {
        guard let url = Bundle.main.url(forResource: "owl-\(kind)", withExtension: "caf"),
              let sound = NSSound(contentsOf: url, byReference: true)
        else { return }
        sound.play()
        let end = Date().addingTimeInterval(sound.duration + 0.2)
        while sound.isPlaying && Date() < end { RunLoop.main.run(until: Date().addingTimeInterval(0.05)) }
    }

    static func fail(_ message: String) -> Int32 {
        FileHandle.standardError.write("PIA notify: \(message)\n".data(using: .utf8)!)
        return 2
    }
}
