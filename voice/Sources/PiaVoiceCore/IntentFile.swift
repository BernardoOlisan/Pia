import Foundation

/// What pia-voice reads from the Lead's `intent.md`. The voice never writes it.
public enum IntentFile {
    /// The Lead writes this line when the intent is finished and waits for the human's confirmation.
    public static let readyMarker = "<!-- pia-voice: ready to confirm -->"

    public struct Round: Equatable {
        public let number: Int
        /// The round's text as written by the Lead: questions and suggested answers.
        public let text: String
        public let questionCount: Int
        /// Questions without an answer yet (an answered question has "→").
        public let unansweredCount: Int
    }

    public struct State: Equatable {
        public var rounds: [Round] = []
        public var readyToConfirm = false
        /// Everything above "## Decided by the human" (or "## Clarifications").
        public var summary = ""

        /// The first round that still has unanswered questions.
        public func openRound(excluding sent: Set<Int> = []) -> Round? {
            rounds.first { $0.unansweredCount > 0 && !sent.contains($0.number) }
        }
    }

    public static func read(_ url: URL) -> State {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return State() }
        return parse(text)
    }

    public static func parse(_ text: String) -> State {
        var state = State()
        state.readyToConfirm = text.contains(readyMarker)
        let lines = text.components(separatedBy: "\n")

        var summaryLines: [String] = []
        for line in lines {
            if line.hasPrefix("## Decided by the human") || line.hasPrefix("## Clarifications") { break }
            if line.contains(readyMarker) { continue }
            summaryLines.append(line)
        }
        state.summary = summaryLines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)

        var current: (number: Int, lines: [String])?
        func close() {
            guard let c = current else { return }
            let body = c.lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            let questions = c.lines.filter { isQuestion($0) }
            let unanswered = questions.filter { !$0.contains("→") && !$0.contains("->") }
            state.rounds.append(Round(number: c.number, text: body,
                                      questionCount: questions.count, unansweredCount: unanswered.count))
            current = nil
        }
        for line in lines {
            if line.hasPrefix("### Round ") {
                close()
                let digits = line.dropFirst("### Round ".count).prefix { $0.isNumber }
                if let n = Int(digits) { current = (n, []) }
                continue
            }
            if line.hasPrefix("## ") || line.hasPrefix("### ") { close(); continue }
            current?.lines.append(line)
        }
        close()
        return state
    }

    private static func isQuestion(_ line: String) -> Bool {
        let trimmed = line.drop { $0 == " " }
        let digits = trimmed.prefix { $0.isNumber }
        return !digits.isEmpty && trimmed.dropFirst(digits.count).hasPrefix(". ") && line.first != " "
    }
}
