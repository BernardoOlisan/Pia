import Foundation

/// Runs a program without a shell and returns its exit code and output.
public enum Shell {
    @discardableResult
    public static func run(_ path: String, _ args: [String], input: String? = nil, timeout: TimeInterval = 20) -> (code: Int32, out: String) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: path)
        p.arguments = args
        let out = Pipe()
        p.standardOutput = out
        p.standardError = out
        let inPipe = Pipe()
        p.standardInput = input == nil ? FileHandle.nullDevice : inPipe
        do { try p.run() } catch { return (-1, "\(error)") }
        if let input {
            inPipe.fileHandleForWriting.write(Data(input.utf8))
            try? inPipe.fileHandleForWriting.close()
        }
        let deadline = Date().addingTimeInterval(timeout)
        while p.isRunning && Date() < deadline { usleep(20_000) }
        if p.isRunning { p.terminate(); return (-2, "timed out") }
        let data = out.fileHandleForReading.readDataToEndOfFile()
        return (p.terminationStatus, String(data: data, encoding: .utf8) ?? "")
    }

    /// The four power commands PIA may run as root. The sudoers rule installed by awake-install.sh
    /// allows exactly these and nothing else, without a password.
    public static func pmset(_ args: [String]) -> Bool {
        run("/usr/bin/sudo", ["-n", "/usr/bin/pmset"] + args).code == 0
    }

    /// Whether the sudoers rule is in place: `sudo -n -l <command>` succeeds only for allowed commands.
    public static func pmsetAllowed() -> Bool {
        run("/usr/bin/sudo", ["-n", "-l", "/usr/bin/pmset", "-a", "disablesleep", "1"]).code == 0
    }
}
