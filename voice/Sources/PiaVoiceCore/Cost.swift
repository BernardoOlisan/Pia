import Foundation

/// GPT-Live bills voice time at $0.05 per minute, per second, silence included.
/// `session.usage.updated` gives cumulative seconds per session; sessions add up for the work.
public struct CostMeter: Equatable {
    public static let dollarsPerMinute = 0.05

    public private(set) var closedSeconds: Double = 0
    public private(set) var sessionSeconds: Double = 0
    public private(set) var backendInputTokens = 0
    public private(set) var backendOutputTokens = 0

    public init(closedSeconds: Double = 0) { self.closedSeconds = closedSeconds }

    public var seconds: Double { closedSeconds + sessionSeconds }
    public var dollars: Double { seconds / 60 * Self.dollarsPerMinute }
    public var label: String { String(format: "$%.2f", dollars) }

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
