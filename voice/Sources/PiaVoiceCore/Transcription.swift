import Foundation

/// File transcription with OpenAI's `gpt-transcribe`: one recorded dictation in, its text out.
/// Billed by audio duration, nothing for silence before or after (it's a file, not a session).
public enum Transcription {
    public static let url = URL(string: "https://api.openai.com/v1/audio/transcriptions")!
    public static let model = "gpt-transcribe"
    public static let dollarsPerMinute = 0.0045

    /// Hints for the model: a dictation for a coding agent, in Spanish, English or both.
    public struct Context: Equatable {
        public var languages: [String]
        public var keywords: [String]
        public var prompt: String

        public init(languages: [String] = ["es", "en"],
                    keywords: [String] = ["Claude", "Claude Code", "PIA", "OpenAI"],
                    prompt: String = "Dictation of a message for a coding agent. Spanish, English and Spanglish are mixed; keep every word in the language it was spoken.") {
            self.languages = languages
            self.keywords = keywords
            self.prompt = prompt
        }
    }

    public struct Result: Equatable {
        public var text: String
        /// Billed seconds, when the response reports them.
        public var seconds: Double?
    }

    public enum Failure: Error, CustomStringConvertible {
        case http(Int, String)
        case unreadable(String)

        public var description: String {
            switch self {
            case .http(let code, let body): return "HTTP \(code): \(body.prefix(300))"
            case .unreadable(let body): return "unreadable response: \(body.prefix(300))"
            }
        }
    }

    public static func request(apiKey: String, audio: Data, filename: String, context: Context = Context()) -> URLRequest {
        let boundary = "pia-" + UUID().uuidString
        var request = URLRequest(url: url, timeoutInterval: 180)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.httpBody = multipart(audio: audio, filename: filename, context: context, boundary: boundary)
        return request
    }

    /// Array fields go as repeated `name[]` parts.
    public static func multipart(audio: Data, filename: String, context: Context, boundary: String) -> Data {
        var body = Data()
        func field(_ name: String, _ value: String) {
            body.append("--\(boundary)\r\nContent-Disposition: form-data; name=\"\(name)\"\r\n\r\n\(value)\r\n".data(using: .utf8)!)
        }
        field("model", model)
        for language in context.languages { field("languages[]", language) }
        for keyword in context.keywords { field("keywords[]", keyword) }
        if !context.prompt.isEmpty { field("prompt", context.prompt) }
        body.append("--\(boundary)\r\nContent-Disposition: form-data; name=\"file\"; filename=\"\(filename)\"\r\nContent-Type: audio/mp4\r\n\r\n".data(using: .utf8)!)
        body.append(audio)
        body.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)
        return body
    }

    /// `{"text": …, "usage": {"type": "duration", "seconds": 6}}`
    public static func parse(_ data: Data) -> Result? {
        guard let object = (try? JSONSerialization.jsonObject(with: data)) as? JSONObject,
              let text = object["text"] as? String
        else { return nil }
        let usage = object["usage"] as? JSONObject
        let seconds = usage?["type"] as? String == "duration" ? (usage?["seconds"] as? NSNumber)?.doubleValue : nil
        return Result(text: text, seconds: seconds)
    }

    public static func send(apiKey: String, audioFile: URL, context: Context = Context()) async throws -> Result {
        let audio = try Data(contentsOf: audioFile)
        let (data, response) = try await URLSession.shared.data(for: request(apiKey: apiKey, audio: audio, filename: audioFile.lastPathComponent, context: context))
        let body = String(data: data, encoding: .utf8) ?? ""
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else { throw Failure.http(status, body) }
        guard let result = parse(data) else { throw Failure.unreadable(body) }
        return result
    }
}

/// What dictation has cost this month. Kept in a small JSON file; a new month starts from zero.
public struct DictationLedger: Codable, Equatable {
    public var month: String
    public var seconds: Double
    public var dictations: Int

    public init(month: String, seconds: Double = 0, dictations: Int = 0) {
        self.month = month
        self.seconds = seconds
        self.dictations = dictations
    }

    public static func monthKey(_ date: Date) -> String {
        let parts = Calendar(identifier: .gregorian).dateComponents([.year, .month], from: date)
        return String(format: "%04d-%02d", parts.year ?? 0, parts.month ?? 0)
    }

    public mutating func add(seconds more: Double, at date: Date = Date()) {
        let key = Self.monthKey(date)
        if key != month { self = DictationLedger(month: key) }
        seconds += max(0, more)
        dictations += 1
    }

    /// This month's dollars, plus a recording still in progress.
    public func dollars(at date: Date = Date(), pendingSeconds: Double = 0) -> Double {
        let base = Self.monthKey(date) == month ? seconds : 0
        return (base + max(0, pendingSeconds)) / 60 * Transcription.dollarsPerMinute
    }

    /// Under a dollar the third decimal is where dictation moves: `$0.004`, then `$1.25`.
    public static func label(_ dollars: Double) -> String {
        String(format: dollars < 1 ? "$%.3f" : "$%.2f", dollars)
    }

    public static func load(_ url: URL, now: Date = Date()) -> DictationLedger {
        if let data = try? Data(contentsOf: url), let ledger = try? JSONDecoder().decode(DictationLedger.self, from: data) {
            return ledger
        }
        return DictationLedger(month: monthKey(now))
    }

    public func save(_ url: URL) {
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let data = try? JSONEncoder().encode(self) { try? data.write(to: url, options: .atomic) }
    }
}

/// A global shortcut written as text, e.g. `option+space` or `ctrl+shift+d`. Carbon key codes and modifiers.
public struct HotkeySpec: Equatable, CustomStringConvertible {
    public var keyCode: UInt32
    public var modifiers: UInt32
    public var description: String

    public static let `default` = HotkeySpec.parse("option+space")!
    static let shiftBit: UInt32 = 512

    /// The same shortcut with ⇧ added: the take that appends to the one before it instead of replacing it.
    /// Nil when the shortcut already uses ⇧ and there is no free variant of it.
    public var withShift: HotkeySpec? {
        guard modifiers & Self.shiftBit == 0 else { return nil }
        var parts = description.split(separator: "+").map(String.init)
        let key = parts.popLast() ?? "space"
        parts.append(contentsOf: ["shift", key])
        return HotkeySpec(keyCode: keyCode, modifiers: modifiers | Self.shiftBit,
                          description: parts.joined(separator: "+"))
    }

    static let modifierBits: [String: UInt32] = [
        "cmd": 256, "command": 256, "shift": 512, "option": 2048, "opt": 2048, "alt": 2048, "ctrl": 4096, "control": 4096,
    ]
    static let keyCodes: [String: UInt32] = [
        "a": 0, "s": 1, "d": 2, "f": 3, "h": 4, "g": 5, "z": 6, "x": 7, "c": 8, "v": 9, "b": 11, "q": 12, "w": 13,
        "e": 14, "r": 15, "y": 16, "t": 17, "1": 18, "2": 19, "3": 20, "4": 21, "6": 22, "5": 23, "9": 25, "7": 26,
        "8": 28, "0": 29, "o": 31, "u": 32, "i": 34, "p": 35, "l": 37, "j": 38, "k": 40, "n": 45, "m": 46,
        "space": 49, "return": 36, "enter": 36, "escape": 53, "esc": 53,
    ]

    /// Needs at least one modifier, so a plain key is never taken from every app.
    public static func parse(_ text: String) -> HotkeySpec? {
        let parts = text.lowercased().split(separator: "+").map { $0.trimmingCharacters(in: .whitespaces) }
        guard let key = parts.last, let code = keyCodes[key], parts.count >= 2 else { return nil }
        var bits: UInt32 = 0
        for name in parts.dropLast() {
            guard let bit = modifierBits[name] else { return nil }
            bits |= bit
        }
        return HotkeySpec(keyCode: code, modifiers: bits, description: parts.joined(separator: "+"))
    }
}
