import Foundation

/// The channel between the voice and Claude. There is no protocol and no rounds.
///
/// **Out:** lines on stdout, which reach the Lead as events.
/// **In:** an append-only file the Lead writes, one message per line. Each line is something to say,
/// in the Lead's own words, whenever the Lead has something to say.
///
/// The old design put a second model between them and passed six-field forms through `talk.md`, with
/// numbered rounds and a poll asking whether the next round was ready. That is why it sounded like a
/// form being filled in. Claude is the brain now; the voice is its mouth, and this is the air between.
public final class VoiceBridge {
    public let inbox: URL
    public private(set) var ended = false
    public private(set) var endReason = ""
    /// Lines already handed to the voice, so a poll only ever returns what is new.
    private var consumed = 0
    private let emit: (String) -> Void

    public init(inbox: URL, emit: @escaping (String) -> Void) {
        self.inbox = inbox
        self.emit = emit
    }

    /// Everything the Lead has written since the last call. Blank lines are separators, not messages.
    public func newMessages() -> [String] {
        guard let text = try? String(contentsOf: inbox, encoding: .utf8) else { return [] }
        let lines = text
            .components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        guard lines.count > consumed else {
            // The Lead replaced the file instead of appending: start again rather than repeat old lines.
            if lines.count < consumed { consumed = lines.count }
            return []
        }
        let fresh = Array(lines[consumed...])
        consumed = lines.count
        return fresh
    }

    // MARK: The tools the voice can call

    public func handle(name: String, arguments: String) -> String {
        let args = JSON.decode(arguments) ?? [:]
        switch name {
        case "tell_claude":
            guard let text = (args["text"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !text.isEmpty
            else { return result(["ok": false, "error": "text is required"]) }
            emit("PIA-VOICE SAID " + JSON.encode(["text": text]))
            return result(["ok": true, "note": "Claude has it. Keep talking; his answer will reach you when he has one."])

        case "end_voice":
            ended = true
            endReason = (args["reason"] as? String) ?? "the human asked to stop the voice"
            return result(["ok": true, "note": "Say goodbye in one short sentence. Claude carries on in the terminal."])

        default:
            return result(["ok": false, "error": "unknown tool \(name)"])
        }
    }

    public func endedLine(reason: String) -> String {
        "PIA-VOICE ENDED " + JSON.encode(["reason": reason])
    }

    private func result(_ object: JSONObject) -> String { JSON.encode(object) }
}
