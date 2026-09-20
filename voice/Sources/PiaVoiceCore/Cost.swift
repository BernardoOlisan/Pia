import Foundation

/// What a voice talk costs, both halves of it.
///
/// GPT-Live bills voice time at $0.05 per minute, per second, silence included, and
/// `session.usage.updated` reports the cumulative seconds of the open session.
///
/// The backend model is billed separately, in tokens, and it is not small: it receives the whole
/// conversation again every time it decides whether to call a tool. Leaving it out of the number was
/// showing perhaps half of what a talk really cost.
public struct CostMeter: Equatable {
    public static let dollarsPerMinute = 0.05
    /// Estimated, not confirmed. Shown as an estimate, and overridable, rather than quoted as fact.
    public static var backendDollarsPerMillionInput = 1.25
    public static var backendDollarsPerMillionOutput = 10.0

    public private(set) var closedSeconds: Double = 0
    public private(set) var sessionSeconds: Double = 0
    public private(set) var backendInputTokens = 0
    public private(set) var backendOutputTokens = 0

    public init(closedSeconds: Double = 0) { self.closedSeconds = closedSeconds }

    public var seconds: Double { closedSeconds + sessionSeconds }
    public var voiceDollars: Double { seconds / 60 * Self.dollarsPerMinute }
    public var backendDollars: Double {
        Double(backendInputTokens) / 1_000_000 * Self.backendDollarsPerMillionInput
            + Double(backendOutputTokens) / 1_000_000 * Self.backendDollarsPerMillionOutput
    }
    public var dollars: Double { voiceDollars + backendDollars }
    /// What the island shows on a double click: everything this talk has cost so far.
    public var label: String { String(format: "$%.2f", dollars) }

    /// The full picture, for the log and for the Lead to read out. The backend half is an estimate.
    public var breakdown: String {
        String(format: "voice %@ (%.0fs) + backend ~%@ (%d in / %d out tokens) = %@ total",
               String(format: "$%.2f", voiceDollars), seconds,
               String(format: "$%.2f", backendDollars),
               backendInputTokens, backendOutputTokens, label)
    }

    /// A cumulative snapshot for the current session.
    public mutating func update(sessionSeconds: Double) {
        self.sessionSeconds = max(self.sessionSeconds, sessionSeconds)
    }

    public mutating func closeSession(finalSeconds: Double?) {
        closedSeconds += max(sessionSeconds, finalSeconds ?? 0)
        sessionSeconds = 0
    }

    public mutating func addBackend(inputTokens: Int, outputTokens: Int) {
        backendInputTokens += inputTokens
        backendOutputTokens += outputTokens
    }
}
