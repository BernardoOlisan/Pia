import Foundation

/// The prompt files in `voice/prompts/intent/`. Kept outside the code so they can be edited without Swift.
public struct Prompts {
    public var voice: String
    public var backend: String
    public var tools: [JSONObject]
    public var notices: [String: String]

    public enum LoadError: Error, CustomStringConvertible {
        case notFound
        case unreadable(String)
        public var description: String {
            switch self {
            case .notFound: return "prompts folder not found (pass --prompts <dir>)"
            case .unreadable(let file): return "could not read \(file)"
            }
        }
    }

    public static func load(dir: URL) throws -> Prompts {
        func text(_ name: String) throws -> String {
            guard let s = try? String(contentsOf: dir.appendingPathComponent(name), encoding: .utf8) else {
                throw LoadError.unreadable(name)
            }
            return s
        }
        guard let tools = JSON.decodeAny(try text("tools.json")) as? [JSONObject] else {
            throw LoadError.unreadable("tools.json")
        }
        return Prompts(voice: try text("voice.md"), backend: try text("backend.md"),
                       tools: tools, notices: parseNotices(try text("notices.md")))
    }

    /// `## key` sections, body until the next section.
    public static func parseNotices(_ text: String) -> [String: String] {
        var result: [String: String] = [:]
        var key: String?
        var body: [String] = []
        func flush() {
            if let key { result[key] = body.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines) }
            body = []
        }
        for line in text.components(separatedBy: "\n") {
            if line.hasPrefix("## ") {
                flush()
                key = String(line.dropFirst(3)).trimmingCharacters(in: .whitespaces)
            } else if line.hasPrefix("# ") {
                flush()
                key = nil
            } else if key != nil {
                body.append(line)
            }
        }
        flush()
        return result
    }

    public func notice(_ key: String, text: String = "") -> String {
        (notices[key] ?? key).replacingOccurrences(of: "{text}", with: text)
    }

    /// `--prompts`, then `PIA_VOICE_PROMPTS`, then a `prompts/intent` folder above the executable.
    public static func locate(override: String?) -> URL? {
        let fm = FileManager.default
        if let override { return URL(fileURLWithPath: override) }
        if let env = ProcessInfo.processInfo.environment["PIA_VOICE_PROMPTS"] { return URL(fileURLWithPath: env) }
        var dir = URL(fileURLWithPath: CommandLine.arguments[0]).resolvingSymlinksInPath().deletingLastPathComponent()
        for _ in 0..<8 {
            let candidate = dir.appendingPathComponent("prompts/intent")
            if fm.fileExists(atPath: candidate.appendingPathComponent("voice.md").path) { return candidate }
            dir.deleteLastPathComponent()
        }
        return nil
    }
}
