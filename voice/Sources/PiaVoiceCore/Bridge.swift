import Foundation

/// Lines on stdout are the bridge to the Lead: every line reaches Claude Code as an event.
public final class Emitter {
    private let lock = NSLock()
    public init() {}

    public func line(_ text: String) {
        lock.lock(); defer { lock.unlock() }
        let single = text.replacingOccurrences(of: "\n", with: " ")
        FileHandle.standardOutput.write((single + "\n").data(using: .utf8)!)
    }

    /// Diagnostics go to stderr, so they never become events for the Lead.
    public func debug(_ text: String) {
        FileHandle.standardError.write(("pia-voice: " + text + "\n").data(using: .utf8)!)
    }
}

/// Exits pia-voice when the Claude Code process that started it is gone.
public final class ParentWatch {
    private var timer: Timer?

    public init() {}

    public func start(onGone: @escaping () -> Void) {
        guard let raw = ProcessInfo.processInfo.environment["CLAUDE_PID"], let pid = pid_t(raw), pid > 1 else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { _ in
            if kill(pid, 0) != 0 && errno == ESRCH { onGone() }
        }
    }
}

/// Polls a file's modification date. Survives editors that replace the file.
public final class FilePoller {
    private let url: URL
    private var last: Date?
    private var timer: Timer?

    public init(url: URL) { self.url = url }

    public func start(interval: TimeInterval = 0.5, onChange: @escaping () -> Void) {
        last = modified()
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            guard let self else { return }
            let now = self.modified()
            if now != self.last {
                self.last = now
                onChange()
            }
        }
    }

    private func modified() -> Date? {
        (try? FileManager.default.attributesOfItem(atPath: url.path))?[.modificationDate] as? Date
    }
}
