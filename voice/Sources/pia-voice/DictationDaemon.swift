import Darwin
import Foundation

/// The one dictation process per Mac: its PID file, and how the hooks start, signal and replace it.
///
/// `dictate.pid` holds three lines: PID, executable path, start time. A process is only trusted as the
/// daemon when that PID is alive and still runs a `pia-voice` binary.
enum DictationDaemon {
    struct Record {
        var pid: pid_t
        var executable: String
        var started: TimeInterval
    }

    static var executable: String {
        (Bundle.main.executableURL ?? URL(fileURLWithPath: CommandLine.arguments[0])).resolvingSymlinksInPath().path
    }

    static func writeRecord() {
        let text = "\(getpid())\n\(executable)\n\(Date().timeIntervalSince1970)\n"
        try? text.write(to: DictationPaths.pid, atomically: true, encoding: .utf8)
    }

    static func removeRecord() {
        if let record = read(), record.pid == getpid() { try? FileManager.default.removeItem(at: DictationPaths.pid) }
    }

    static func read() -> Record? {
        guard let text = try? String(contentsOf: DictationPaths.pid, encoding: .utf8) else { return nil }
        let lines = text.split(separator: "\n").map(String.init)
        guard lines.count >= 3, let pid = pid_t(lines[0]), let started = TimeInterval(lines[2]) else { return nil }
        return Record(pid: pid, executable: lines[1], started: started)
    }

    static func running() -> Record? {
        guard let record = read(), record.pid > 1, kill(record.pid, 0) == 0 else { return nil }
        var buffer = [CChar](repeating: 0, count: 4 * Int(MAXPATHLEN))
        guard proc_pidpath(record.pid, &buffer, UInt32(buffer.count)) > 0,
              URL(fileURLWithPath: String(cString: buffer)).lastPathComponent == "pia-voice"
        else { return nil }
        return record
    }

    /// `/pia:transcribe`: tell the running daemon to start or stop, or start one already recording.
    static func toggle() -> Int32 {
        if let record = running() {
            kill(record.pid, SIGUSR1)
            return 0
        }
        return spawn(["--record"])
    }

    /// Session start: make sure a daemon runs, and that it's this build. An older one is asked to quit
    /// (it finishes a dictation in progress first, and then the next session start replaces it).
    static func ensure() -> Int32 {
        if let record = running() {
            let modified = (try? FileManager.default.attributesOfItem(atPath: executable)[.modificationDate] as? Date)?
                .timeIntervalSince1970 ?? 0
            guard record.executable != executable || modified > record.started else { return 0 }
            kill(record.pid, SIGTERM)
            for _ in 0..<20 where running() != nil { usleep(100_000) }
            if running() != nil { return 0 }
        }
        return spawn([])
    }

    static func stop() -> Int32 {
        if let record = running() { kill(record.pid, SIGTERM) }
        return 0
    }

    /// A detached `pia-voice dictate serve`, in its own session so it outlives the hook that started it.
    private static func spawn(_ extra: [String]) -> Int32 {
        try? FileManager.default.createDirectory(at: DictationPaths.dir, withIntermediateDirectories: true)
        var attributes: posix_spawnattr_t?
        posix_spawnattr_init(&attributes)
        posix_spawnattr_setflags(&attributes, Int16(POSIX_SPAWN_SETSID))
        var actions: posix_spawn_file_actions_t?
        posix_spawn_file_actions_init(&actions)
        posix_spawn_file_actions_addopen(&actions, 0, "/dev/null", O_RDONLY, 0)
        posix_spawn_file_actions_addopen(&actions, 1, DictationPaths.log.path, O_WRONLY | O_CREAT | O_APPEND, 0o644)
        posix_spawn_file_actions_adddup2(&actions, 1, 2)
        defer {
            posix_spawnattr_destroy(&attributes)
            posix_spawn_file_actions_destroy(&actions)
        }

        let arguments = [executable, "dictate", "serve"] + extra
        var argv: [UnsafeMutablePointer<CChar>?] = arguments.map { strdup($0) } + [nil]
        defer { argv.forEach { free($0) } }
        var pid: pid_t = 0
        let status = posix_spawn(&pid, executable, &actions, &attributes, &argv, environ)
        if status != 0 {
            FileHandle.standardError.write("pia-voice: could not start dictation (\(String(cString: strerror(status))))\n".data(using: .utf8)!)
            return 2
        }
        return 0
    }
}
