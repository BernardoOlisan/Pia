import Foundation
import Observation

/// What the intent island shows. Updated on the main thread by the session.
@Observable
public final class NotchModel {
    /// A GPT-Live session is open.
    public var connected = false
    /// "$0.35": voice cost so far for this work. Hidden unless asked for.
    public var cost = "$0.00"
    /// Double-clicking the island shows the cost; double-clicking again hides it.
    public var showCost = false
    /// How long this work has been talking. GPT-Live bills by the second, so the clock is the cost.
    public var elapsed: TimeInterval = 0
    /// 0...1, the loudest of microphone and voice.
    public var level: Float = 0
    /// The voice is the one making sound right now.
    public var voiceSpeaking = false
    /// The last couple of seconds of loudness, oldest first.
    public var samples: [Float] = []
    /// One click ends the voice.
    public var onDotClick: (() -> Void)?

    public init() {}

    public func push(level: Float) {
        self.level = level
        samples.append(level)
        if samples.count > Waveform.capacity { samples.removeFirst(samples.count - Waveform.capacity) }
    }
}
