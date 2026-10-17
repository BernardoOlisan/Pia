import Foundation

/// Every file PIA.app keeps, in one place: `~/Library/Application Support/PIA/`.
public enum PiaPaths {
    public static var support: URL {
        if let custom = ProcessInfo.processInfo.environment["PIA_APP_SUPPORT"], !custom.isEmpty {
            return URL(fileURLWithPath: custom, isDirectory: true)
        }
        return FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/PIA", isDirectory: true)
    }

    public static var awake: URL { support.appendingPathComponent("awake", isDirectory: true) }
    /// One file per running work: line 1 its folder, line 2 the PID of its caffeinate.
    public static var claims: URL { awake.appendingPathComponent("claims", isDirectory: true) }
    /// What the daemon sees and does, rewritten every few seconds (the mod's band reads it).
    public static var status: URL { awake.appendingPathComponent("status.json") }
    /// Written *before* PIA changes a power setting, so a crash can always be undone.
    public static var journal: URL { awake.appendingPathComponent("journal.json") }
    public static var settings: URL { awake.appendingPathComponent("settings.json") }
    public static var pid: URL { awake.appendingPathComponent("awake.pid") }
    public static var log: URL { awake.appendingPathComponent("awake.log") }
    public static var hotspot: URL { support.appendingPathComponent("hotspot.json") }

    public static func ensure() {
        try? FileManager.default.createDirectory(at: claims, withIntermediateDirectories: true)
    }
}

/// A work that asked to be kept awake.
public struct Claim: Equatable, Sendable {
    public var file: URL
    public var workDir: String
    public var caffeinatePID: Int32

    public static func parse(file: URL, text: String) -> Claim? {
        let lines = text.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) }
        guard lines.count >= 2, !lines[0].isEmpty, let pid = Int32(lines[1]), pid > 1 else { return nil }
        return Claim(file: file, workDir: lines[0], caffeinatePID: pid)
    }

    public static func all(in folder: URL = PiaPaths.claims) -> [Claim] {
        let files = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
        return files.compactMap { file in
            guard let text = try? String(contentsOf: file, encoding: .utf8) else { return nil }
            return parse(file: file, text: text)
        }
    }
}

/// What PIA changed and must undo. Written before each change, cleared after the undo.
public struct Journal: Codable, Equatable, Sendable {
    public var sleepDisabled = false
    public var lowPowerSet = false
    public var since: Date?

    public init() {}

    public static func read(_ url: URL = PiaPaths.journal) -> Journal {
        guard let data = try? Data(contentsOf: url), let j = try? JSONDecoder().decode(Journal.self, from: data) else {
            return Journal()
        }
        return j
    }

    public func write(_ url: URL = PiaPaths.journal) {
        if let data = try? JSONEncoder().encode(self) { try? data.write(to: url, options: .atomic) }
    }

    public var isClean: Bool { !sleepDisabled && !lowPowerSet }
}

/// The band in the terminal and `awake.sh status` read this.
public struct AwakeStatus: Codable, Equatable, Sendable {
    public var updated: Date
    public var installed: Bool
    public var runningWorks: [String]
    public var holdingAwake: Bool
    public var reason: String
    public var lidClosed: Bool
    public var battery: Int?
    public var onAC: Bool
    public var lowPower: Bool
    public var thermal: Int
    /// wifi | hotspot | wired | none
    public var network: String
    public var hotspotConfigured: Bool

    public init(updated: Date, installed: Bool, runningWorks: [String], holdingAwake: Bool, reason: String,
                lidClosed: Bool, battery: Int?, onAC: Bool, lowPower: Bool, thermal: Int, network: String,
                hotspotConfigured: Bool) {
        self.updated = updated
        self.installed = installed
        self.runningWorks = runningWorks
        self.holdingAwake = holdingAwake
        self.reason = reason
        self.lidClosed = lidClosed
        self.battery = battery
        self.onAC = onAC
        self.lowPower = lowPower
        self.thermal = thermal
        self.network = network
        self.hotspotConfigured = hotspotConfigured
    }
}

public struct HotspotConfig: Codable, Equatable, Sendable {
    public var ssid: String
    /// Seconds without any network before PIA joins the hotspot.
    public var after: Double = 45

    public init(ssid: String, after: Double = 45) {
        self.ssid = ssid
        self.after = after
    }
}
