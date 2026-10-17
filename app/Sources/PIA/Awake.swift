import AppKit
import Darwin
import Foundation
import Network
import PiaAppCore

/// PIA Awake: the Mac stays up with the lid closed while any work runs, and sleeps again when none does.
///
///   PIA awake ensure    start the daemon if it isn't running (awake.sh start does this)
///   PIA awake serve     the daemon itself
///   PIA awake status    what it sees, as JSON
///   PIA awake recover   undo PIA's power changes if the daemon died holding them (launchd, every minute)
///   PIA awake stop      ask the daemon to undo everything and quit
///
/// Works register by dropping a claim file (awake.sh): their folder and the PID of their caffeinate.
/// A claim counts while that caffeinate is alive — it watches Claude Code, so a crash releases it too.
enum Awake {
    static func run(_ arguments: [String]) -> Int32 {
        PiaPaths.ensure()
        switch arguments.first ?? "status" {
        case "ensure": return ensure()
        case "serve": return Daemon.serve()
        case "status": return status()
        case "recover": return recover()
        case "stop":
            if let pid = runningPID() { kill(pid, SIGTERM) }
            return 0
        default:
            FileHandle.standardError.write("usage: PIA awake ensure|serve|status|recover|stop\n".data(using: .utf8)!)
            return 2
        }
    }

    static var executable: String {
        (Bundle.main.executableURL ?? URL(fileURLWithPath: CommandLine.arguments[0])).resolvingSymlinksInPath().path
    }

    static func runningPID() -> pid_t? {
        guard let text = try? String(contentsOf: PiaPaths.pid, encoding: .utf8),
              let pid = pid_t(text.split(separator: "\n").first ?? ""), pid > 1, kill(pid, 0) == 0
        else { return nil }
        var buffer = [CChar](repeating: 0, count: 4 * Int(MAXPATHLEN))
        guard proc_pidpath(pid, &buffer, UInt32(buffer.count)) > 0,
              URL(fileURLWithPath: String(cString: buffer)).lastPathComponent == "PIA"
        else { return nil }
        return pid
    }

    static func ensure() -> Int32 {
        if runningPID() != nil { return 0 }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: executable)
        p.arguments = ["awake", "serve"]
        p.standardInput = FileHandle.nullDevice
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        do { try p.run() } catch { return 1 }
        for _ in 0..<30 where runningPID() == nil { usleep(100_000) }
        return runningPID() == nil ? 1 : 0
    }

    static func status() -> Int32 {
        if runningPID() == nil {
            print(#"{"running":false}"#)
            return 0
        }
        print((try? String(contentsOf: PiaPaths.status, encoding: .utf8)) ?? #"{"running":true}"#)
        return 0
    }

    /// The crash path: nobody is holding the Mac awake on purpose, so put back what the journal says.
    static func recover() -> Int32 {
        guard runningPID() == nil else { return 0 }
        var journal = Journal.read()
        guard !journal.isClean || Power.sleepDisabled() else { return 0 }
        if journal.sleepDisabled || Power.sleepDisabled() {
            if Shell.pmset(["-a", "disablesleep", "0"]) { journal.sleepDisabled = false }
        }
        if journal.lowPowerSet, Shell.pmset(["-a", "lowpowermode", "0"]) { journal.lowPowerSet = false }
        journal.write()
        AwakeLog.write("recover: undid PIA's power changes (no daemon was running)")
        return 0
    }

    static func isCaffeinate(_ pid: Int32) -> Bool {
        guard pid > 1, kill(pid, 0) == 0 else { return false }
        var buffer = [CChar](repeating: 0, count: 4 * Int(MAXPATHLEN))
        guard proc_pidpath(pid, &buffer, UInt32(buffer.count)) > 0 else { return false }
        return URL(fileURLWithPath: String(cString: buffer)).lastPathComponent == "caffeinate"
    }
}

enum AwakeLog {
    static func write(_ line: String) {
        let stamp = ISO8601DateFormatter().string(from: Date())
        let text = "\(stamp) \(line)\n"
        if let handle = try? FileHandle(forWritingTo: PiaPaths.log) {
            handle.seekToEndOfFile()
            handle.write(Data(text.utf8))
            try? handle.close()
        } else {
            try? text.write(to: PiaPaths.log, atomically: true, encoding: .utf8)
        }
    }
}

/// The daemon. One per Mac; a tick every few seconds.
@MainActor
final class Daemon {
    nonisolated static func serve() -> Int32 {
        if let other = Awake.runningPID(), other != getpid() { return 0 }
        setsid()
        signal(SIGHUP, SIG_IGN)
        try? "\(getpid())\n".write(to: PiaPaths.pid, atomically: true, encoding: .utf8)
        let app = NSApplication.shared
        app.setActivationPolicy(.prohibited)
        MainActor.assumeIsolated {
            let daemon = Daemon()
            daemon.start()
            retained = daemon
        }
        app.run()
        return 0
    }

    nonisolated(unsafe) static var retained: Daemon?

    private var journal = Journal.read()
    private var settings = AwakeSettings()
    private var stoppedForBattery = false
    private var wasLidClosed = false
    private var lastReason: AwakeDecision.Reason = .idle
    private var idleTicks = 0
    private let monitor = NWPathMonitor()
    private var path: NWPath?
    private var offlineSince: Date?
    private var lastJoinAttempt = Date.distantPast
    private var installed = Shell.pmsetAllowed()
    private var signalSources: [DispatchSourceSignal] = []

    func start() {
        if let data = try? Data(contentsOf: PiaPaths.settings), let s = try? JSONDecoder().decode(AwakeSettings.self, from: data) {
            settings = s
        }
        AwakeLog.write("serve: started (pid \(getpid()), sudoers rule \(installed ? "present" : "missing"))")
        monitor.pathUpdateHandler = { [weak self] path in
            DispatchQueue.main.async { MainActor.assumeIsolated { self?.pathChanged(path) } }
        }
        monitor.start(queue: .global(qos: .utility))
        for sig in [SIGTERM, SIGINT] {
            signal(sig, SIG_IGN)
            let source = DispatchSource.makeSignalSource(signal: sig, queue: .main)
            source.setEventHandler { MainActor.assumeIsolated { self.quit(reason: "signal") } }
            source.resume()
            signalSources.append(source)
        }
        Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        tick()
    }

    private func pathChanged(_ path: NWPath) {
        self.path = path
        if path.status == .satisfied {
            offlineSince = nil
        } else if offlineSince == nil {
            offlineSince = Date()
        }
    }

    private func liveClaims() -> [Claim] {
        var live: [Claim] = []
        for claim in Claim.all() {
            if Awake.isCaffeinate(claim.caffeinatePID) {
                live.append(claim)
            } else {
                try? FileManager.default.removeItem(at: claim.file)
                AwakeLog.write("claim released: \(claim.workDir) (its caffeinate is gone)")
            }
        }
        return live
    }

    private func tick() {
        let claims = liveClaims()
        let (battery, onAC) = Power.battery()
        let input = AwakeInputs(runningWorks: claims.count, battery: battery, onAC: onAC,
                                thermal: Power.thermal, stoppedForBattery: stoppedForBattery)
        let decision = AwakePolicy.decide(input, settings)
        if decision.stoppedForBattery && !stoppedForBattery && !claims.isEmpty {
            notify(kind: "stalled", es: ("PIA dejó dormir la Mac", "Batería al \(battery ?? 0) %. Conéctala para que los agentes sigan."),
                   en: ("PIA let the Mac sleep", "Battery at \(battery ?? 0)%. Plug it in so the agents can carry on."))
        }
        if decision.reason == .heat && lastReason != .heat {
            notify(kind: "stalled", es: ("PIA dejó dormir la Mac", "Se calentó demasiado. Sácala de la mochila."),
                   en: ("PIA let the Mac sleep", "It got too hot. Take it out of the bag."))
        }
        stoppedForBattery = decision.stoppedForBattery
        lastReason = decision.reason
        apply(decision)

        let lid = Power.lidClosed()
        if lid && !wasLidClosed && decision.holdAwake { Power.displayOff() }
        wasLidClosed = lid

        maybeJoinHotspot(holding: decision.holdAwake)
        writeStatus(claims: claims, decision: decision, battery: battery, onAC: onAC, lid: lid)

        if claims.isEmpty && journal.isClean {
            idleTicks += 1
            if idleTicks >= 3 { quit(reason: "no work is running") }
        } else {
            idleTicks = 0
        }
    }

    private func apply(_ decision: AwakeDecision) {
        if decision.holdAwake && !journal.sleepDisabled {
            installed = Shell.pmsetAllowed()
            guard installed else { return }
            journal.sleepDisabled = true
            journal.since = Date()
            journal.write()
            if Shell.pmset(["-a", "disablesleep", "1"]) {
                AwakeLog.write("hold: lid-closed sleep disabled")
            } else {
                journal.sleepDisabled = false
                journal.write()
                AwakeLog.write("hold: pmset refused")
            }
        } else if !decision.holdAwake && journal.sleepDisabled {
            if Shell.pmset(["-a", "disablesleep", "0"]) {
                journal.sleepDisabled = false
                journal.write()
                AwakeLog.write("release: sleep allowed again (\(decision.reason.rawValue))")
            }
        }
        if decision.lowPower && !journal.lowPowerSet && !Power.lowPowerMode {
            journal.lowPowerSet = true
            journal.write()
            if Shell.pmset(["-a", "lowpowermode", "1"]) {
                AwakeLog.write("low power on")
            } else {
                journal.lowPowerSet = false
                journal.write()
            }
        } else if !decision.lowPower && journal.lowPowerSet {
            if Shell.pmset(["-a", "lowpowermode", "0"]) {
                journal.lowPowerSet = false
                journal.write()
                AwakeLog.write("low power off")
            }
        }
    }

    private func maybeJoinHotspot(holding: Bool) {
        guard holding, let config = Hotspot.config(), let since = offlineSince,
              Date().timeIntervalSince(since) >= config.after,
              Date().timeIntervalSince(lastJoinAttempt) >= 120
        else { return }
        lastJoinAttempt = Date()
        AwakeLog.write("offline for \(Int(Date().timeIntervalSince(since))) s → joining hotspot \(config.ssid)")
        DispatchQueue.global(qos: .utility).async {
            let ok = Hotspot.join()
            AwakeLog.write(ok ? "hotspot joined" : "hotspot join failed")
        }
    }

    private var networkLabel: String {
        guard let path, path.status == .satisfied else { return "none" }
        if path.usesInterfaceType(.wiredEthernet) { return "wired" }
        if path.usesInterfaceType(.wifi) { return path.isExpensive ? "hotspot" : "wifi" }
        return path.isExpensive ? "hotspot" : "other"
    }

    private func writeStatus(claims: [Claim], decision: AwakeDecision, battery: Int?, onAC: Bool, lid: Bool) {
        let status = AwakeStatus(updated: Date(), installed: installed, runningWorks: claims.map(\.workDir),
                                 holdingAwake: journal.sleepDisabled, reason: decision.reason.rawValue,
                                 lidClosed: lid, battery: battery, onAC: onAC, lowPower: Power.lowPowerMode,
                                 thermal: Power.thermal, network: networkLabel,
                                 hotspotConfigured: Hotspot.config() != nil)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        if let data = try? encoder.encode(status) { try? data.write(to: PiaPaths.status, options: .atomic) }
    }

    private func notify(kind: String, es: (String, String), en: (String, String)) {
        let (title, body) = Language.isSpanish ? es : en
        DispatchQueue.global().async { _ = Notify.post(kind: kind, title: title, body: body) }
    }

    private func quit(reason: String) {
        if journal.sleepDisabled, Shell.pmset(["-a", "disablesleep", "0"]) { journal.sleepDisabled = false }
        if journal.lowPowerSet, Shell.pmset(["-a", "lowpowermode", "0"]) { journal.lowPowerSet = false }
        journal.write()
        try? FileManager.default.removeItem(at: PiaPaths.status)
        if let text = try? String(contentsOf: PiaPaths.pid, encoding: .utf8), text.hasPrefix("\(getpid())") {
            try? FileManager.default.removeItem(at: PiaPaths.pid)
        }
        AwakeLog.write("serve: quit (\(reason))")
        exit(0)
    }
}

/// The human's language for PIA's own messages: `~/.pia/config.json` → "language", else the Mac's.
enum Language {
    static var isSpanish: Bool {
        let file = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".pia/config.json")
        if let data = try? Data(contentsOf: file),
           let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let lang = object["language"] as? String {
            return lang.lowercased().hasPrefix("es")
        }
        return (Locale.preferredLanguages.first ?? "en").hasPrefix("es")
    }
}
