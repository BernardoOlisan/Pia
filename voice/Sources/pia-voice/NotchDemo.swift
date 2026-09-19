import AppKit
import Foundation
import PiaVoiceCore
import PiaVoiceNotch

struct NotchDemoOptions {
    /// `dictation` (Voice Memos) or `voice` (the GPT-Live intent island).
    var island = "dictation"
    /// Pin a style so an external monitor's capsule can be seen on the built-in screen, and the other way round.
    var forcedStyle: IslandStyle?
    /// Walk through the states on its own instead of waiting for clicks.
    var cycle = false
    var quiet = false
}

/// The island with no microphone, no API key and no money spent: a fake voice drives it so the shape,
/// the motion, the screen-following and the Space-following can be judged before anything real runs.
///
/// One click walks to the next state. Two clicks show or hide the cost.
@MainActor
final class NotchDemo {
    private let options: NotchDemoOptions
    private let dictation = DictationModel()
    private let voice = NotchModel()
    private let stage = IslandStage()
    private var window: NotchWindow!
    private var talking = false
    private var nextFlip = Date()
    private var startedAt = Date()
    private var seconds: Double = 0
    private var cycleAt = Date.distantFuture

    init(options: NotchDemoOptions) {
        self.options = options
    }

    func start() {
        if options.island == "voice" {
            voice.connected = true
            voice.onDotClick = { [weak self] in self?.advance() }
            window = NotchWindow(model: voice, stage: stage)
        } else {
            dictation.phase = .recording
            dictation.onTap = { [weak self] in self?.advance() }
            window = NotchWindow(dictation: dictation, stage: stage)
        }
        if !options.quiet {
            window.diagnostics = { line in
                FileHandle.standardError.write(("notch · " + line + "\n").data(using: .utf8)!)
            }
        }
        window.show()
        if let style = options.forcedStyle { window.force(style: style) }

        startedAt = Date()
        if options.cycle { cycleAt = Date().addingTimeInterval(6) }
        Timer.scheduledTimer(withTimeInterval: 1.0 / 20, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }

        say("""
        PIA notch mockup — \(options.island == "voice" ? "GPT-Live voice" : "dictation (Voice Memos)")\
        \(options.forcedStyle == .capsule ? ", forced capsule (external-monitor shape)" : "")\
        \(options.forcedStyle == .notch ? ", forced notch" : "")
          · one click  → next state
          · two clicks → show / hide the cost
          · move the pointer to another screen, or switch Desktop, and it should follow
          · nothing is recorded, nothing is sent, nothing is billed
        Stop it with Ctrl-C.
        """)
    }

    // MARK: The fake voice

    private func tick() {
        let now = Date()
        if now >= nextFlip {
            talking.toggle()
            nextFlip = now.addingTimeInterval(talking ? .random(in: 0.7...2.6) : .random(in: 0.25...1.1))
        }
        // A speech-like envelope: syllables inside a burst, near-silence between bursts.
        let level: Float
        if talking {
            let syllable = 0.5 + 0.5 * sin(now.timeIntervalSinceReferenceDate * 2 * .pi * 3.1)
            level = Float(min(1, 0.22 + 0.62 * syllable + Double.random(in: -0.08...0.16)))
        } else {
            level = Float(Double.random(in: 0...0.05))
        }

        if options.island == "voice" {
            voice.push(level: level)
            voice.voiceSpeaking = talking
            voice.elapsed = now.timeIntervalSince(startedAt)
            voice.cost = String(format: "$%.2f", voice.elapsed / 60 * 0.05)
        } else {
            if dictation.phase == .recording {
                dictation.push(level: level)
                dictation.elapsed = now.timeIntervalSince(startedAt)
                seconds = dictation.elapsed
            }
            dictation.cost = DictationLedger.label(seconds / 60 * Transcription.dollarsPerMinute)
        }

        if options.cycle, now >= cycleAt {
            cycleAt = now.addingTimeInterval(dictation.phase == .recording ? 6 : 2.2)
            advance()
        }
    }

    /// One click: the next state, so every transition can be watched on demand.
    private func advance() {
        guard options.island != "voice" else {
            voice.connected.toggle()
            return
        }
        switch dictation.phase {
        case .recording: dictation.phase = .transcribing
        case .transcribing: dictation.phase = .done
        case .done: dictation.phase = .failed
        case .failed: dictation.phase = .hidden
        case .hidden:
            dictation.reset()
            startedAt = Date()
            dictation.phase = .recording
        }
    }

    private func say(_ text: String) {
        FileHandle.standardError.write((text + "\n").data(using: .utf8)!)
    }
}
