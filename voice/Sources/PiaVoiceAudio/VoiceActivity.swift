import Foundation
import SpeechVAD

/// Local voice activity detection, free: it decides when to open a GPT-Live session.
///
/// Silero VAD (CoreML, 16 kHz, 512-sample chunks) when it loads; otherwise an energy detector,
/// so voice still works offline or if the model can't be downloaded.
public final class VoiceActivity {
    public private(set) var speaking = false

    private var silero: SileroVADModel?
    private var pending: [Float] = []
    private var speechChunks = 0
    private var silentChunks = 0

    // Silero: probability thresholds, counted in 32 ms chunks.
    private let onsetProbability: Float = 0.5
    private let offsetProbability: Float = 0.35
    private let onsetChunks = 3          // ~100 ms of speech opens
    private let offsetChunks = 12        // ~400 ms of silence ends "speaking"

    // Energy fallback, on the 0...1 decibel-curve level (-57...-13 dBFS).
    private let energyOnset: Float = 0.45
    private let energyOffset: Float = 0.3

    public init() {}

    /// Loads Silero; returns which detector is active.
    public func load() async -> String {
        do {
            silero = try await SileroVADModel.fromPretrained(engine: .coreml)
            return "silero (coreml)"
        } catch {
            return "energy (silero unavailable: \(error))"
        }
    }

    /// Feed 16 kHz mono samples. Returns true on the chunk where speech starts.
    public func feed(_ samples: [Float], level: Float) -> Bool {
        var onset = false
        guard let silero else {
            return step(isSpeech: speaking ? level > energyOffset : level > energyOnset, chunkCount: max(1, samples.count / 512))
        }
        pending.append(contentsOf: samples)
        let size = SileroVADModel.chunkSize
        while pending.count >= size {
            let chunk = Array(pending.prefix(size))
            pending.removeFirst(size)
            let p = silero.processChunk(chunk)
            if step(isSpeech: speaking ? p >= offsetProbability : p >= onsetProbability, chunkCount: 1) { onset = true }
        }
        return onset
    }

    private func step(isSpeech: Bool, chunkCount: Int) -> Bool {
        if isSpeech {
            silentChunks = 0
            speechChunks += chunkCount
            if !speaking && speechChunks >= onsetChunks {
                speaking = true
                return true
            }
        } else {
            speechChunks = 0
            silentChunks += chunkCount
            if speaking && silentChunks >= offsetChunks { speaking = false }
        }
        return false
    }

    public func reset() {
        silero?.resetState()
        pending.removeAll()
        speaking = false
        speechChunks = 0
        silentChunks = 0
    }
}
