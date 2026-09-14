import Foundation
import Observation

/// What the notch shows. Updated on the main thread by the session.
@Observable
public final class NotchModel {
    /// A GPT-Live session is open.
    public var connected = false
    /// "$0.00": voice cost so far for this work.
    public var cost = "$0.00"
    /// 0...1, the loudest of microphone and voice.
    public var level: Float = 0
    /// The voice is the one making sound right now.
    public var voiceSpeaking = false
    /// Clicking the dot ends the voice.
    public var onDotClick: (() -> Void)?

    public init() {}
}
