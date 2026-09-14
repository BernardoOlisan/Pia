import Foundation

/// The conversation as text: for `logs/voice.md`, and as history when a new session opens.
///
/// Both sides can talk at the same time (full duplex), so each speaker keeps its own buffer,
/// and a turn is written when that speaker pauses, not when the other one starts.
public final class Transcript {
    public struct Turn: Equatable {
        public let role: String   // "user" or "assistant"
        public let text: String
        public let at: Date
    }

    public private(set) var turns: [Turn] = []
    public var onTurn: ((Turn) -> Void)?
    /// Seconds without new text before a speaker's turn is written.
    public var pause: TimeInterval = 1.2

    private var userText = ""
    private var assistantText = ""
    private var userLast = Date.distantPast
    private var assistantLast = Date.distantPast

    public init() {}

    public func user(_ delta: String, at now: Date = Date()) {
        userText += delta
        userLast = now
    }

    public func assistant(_ delta: String, at now: Date = Date()) {
        assistantText += delta
        assistantLast = now
    }

    /// Writes the turn of any speaker who has paused.
    public func flushPaused(now: Date = Date()) {
        var ready: [(String, Date)] = []
        if !userText.isEmpty, now.timeIntervalSince(userLast) > pause { ready.append(("user", userLast)) }
        if !assistantText.isEmpty, now.timeIntervalSince(assistantLast) > pause { ready.append(("assistant", assistantLast)) }
        for (role, _) in ready.sorted(by: { $0.1 < $1.1 }) { write(role) }
    }

    /// Writes everything pending, the speaker who talked first first.
    public func commit() {
        let order = userLast <= assistantLast ? ["user", "assistant"] : ["assistant", "user"]
        for role in order { write(role) }
    }

    private func write(_ role: String) {
        let raw = role == "user" ? userText : assistantText
        let at = role == "user" ? userLast : assistantLast
        if role == "user" { userText = "" } else { assistantText = "" }
        let text = raw.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
        guard !text.isEmpty else { return }
        let turn = Turn(role: role, text: text, at: at)
        turns.append(turn)
        onTurn?(turn)
    }

    /// The most recent turns that fit the Live limits for a new session (128 messages, 8,192 tokens).
    /// Tokens are estimated at 4 characters each, with a safety margin.
    public func historyItems(maxTokens: Int = 7_000, maxMessages: Int = 120) -> [JSONObject] {
        var picked: [Turn] = []
        var tokens = 0
        for turn in turns.reversed() {
            let cost = turn.text.count / 4 + 8
            if tokens + cost > maxTokens || picked.count >= maxMessages { break }
            tokens += cost
            picked.append(turn)
        }
        return picked.reversed().map { LiveEvents.historyItem(role: $0.role, text: $0.text) }
    }
}
