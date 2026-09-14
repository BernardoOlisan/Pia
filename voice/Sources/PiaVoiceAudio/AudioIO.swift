import AVFoundation
import Foundation

/// Microphone in, speaker out, one AVAudioEngine with voice processing (echo cancellation),
/// so the voice coming out of the speakers is not heard back as the human.
///
/// Capture is delivered as 24 kHz PCM16 (for GPT-Live) and 16 kHz Float (for the VAD).
/// Playback takes 24 kHz PCM16 from GPT-Live.
public final class AudioIO {
    /// Called on the audio queue with one capture chunk: 24 kHz PCM16 and 16 kHz Float.
    public var onCapture: ((_ pcm24: [Int16], _ float16: [Float]) -> Void)?

    public private(set) var echoCancellation = false
    /// 0...1 loudness, already on a decibel curve for the meter.
    public var inputLevel: Float { levelLock.withLock { _inputLevel } }
    public var outputLevel: Float { levelLock.withLock { _outputLevel } }
    public var isPlaying: Bool { ring.count > 0 }

    private let engine = AVAudioEngine()
    private var ring = FloatRing(capacity: 48_000 * 120)
    private var outputRate: Double = 48_000
    private let queue = DispatchQueue(label: "pia-voice.audio")
    private let levelLock = NSLock()
    private var _inputLevel: Float = 0
    private var _outputLevel: Float = 0

    private var toLive: AVAudioConverter?
    private var toVAD: AVAudioConverter?
    private var fromLive: AVAudioConverter?
    private var monoFormat: AVAudioFormat?
    private let liveFormat = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: 24_000, channels: 1, interleaved: true)!
    private let vadFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16_000, channels: 1, interleaved: false)!
    private var feeder: Thread?
    private var running = false

    public init() {}

    /// `inputFiles`: test mode. Speech files instead of the microphone, played in real time one per turn:
    /// the next file starts after the voice has spoken and then stayed quiet for a moment.
    /// `voiceProcessing: false` for plain dictation: nothing plays back, and voice processing would duck other audio.
    public func start(inputFiles: [URL] = [], voiceProcessing: Bool = true) throws {
        let input = engine.inputNode
        if inputFiles.isEmpty && voiceProcessing {
            do {
                try input.setVoiceProcessingEnabled(true)
                echoCancellation = true
            } catch {
                echoCancellation = false
            }
        }

        // Read the output hardware format before the mixer exists: the mixer defaults to 44.1 kHz
        // and a mismatch with the voice-processing output (48 kHz) makes the engine fail to start.
        let outputHardware = engine.outputNode.outputFormat(forBus: 0)
        outputRate = outputHardware.sampleRate > 0 ? outputHardware.sampleRate : 48_000
        let mixer = engine.mainMixerNode
        engine.connect(mixer, to: engine.outputNode, format: outputHardware)

        let playbackFormat = AVAudioFormat(standardFormatWithSampleRate: outputRate, channels: 1)!
        ring = FloatRing(capacity: Int(outputRate) * 120)
        fromLive = AVAudioConverter(from: liveFormat, to: playbackFormat)
        let source = AVAudioSourceNode(format: playbackFormat) { [weak self] _, _, frameCount, bufferList in
            guard let self else { return noErr }
            let buffers = UnsafeMutableAudioBufferListPointer(bufferList)
            guard let data = buffers[0].mData?.assumingMemoryBound(to: Float.self) else { return noErr }
            let frames = Int(frameCount)
            let real = self.ring.read(into: data, frames: frames)
            for b in 1..<max(1, buffers.count) {
                if let other = buffers[b].mData { memcpy(other, data, frames * MemoryLayout<Float>.size) }
            }
            let level = real > 0 ? Self.level(UnsafeBufferPointer(start: data, count: frames)) : 0
            self.levelLock.withLock { self._outputLevel = level }
            return noErr
        }
        engine.attach(source)
        engine.connect(source, to: mixer, format: playbackFormat)

        if inputFiles.isEmpty {
            let hardware = input.outputFormat(forBus: 0)
            guard hardware.sampleRate > 0 else { throw AudioError.noInput }
            let mono = AVAudioFormat(standardFormatWithSampleRate: hardware.sampleRate, channels: 1)!
            monoFormat = mono
            toLive = AVAudioConverter(from: mono, to: liveFormat)
            toVAD = AVAudioConverter(from: mono, to: vadFormat)
            input.installTap(onBus: 0, bufferSize: 1024, format: hardware) { [weak self] buffer, _ in
                self?.captured(buffer)
            }
        }

        engine.prepare()
        try engine.start()
        running = true

        if !inputFiles.isEmpty { try startFeeder(inputFiles) }
    }

    public func stop() {
        running = false
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
    }

    /// Queue GPT-Live audio (24 kHz PCM16 little-endian) for playback.
    public func play(pcm16 data: Data) {
        queue.async { [weak self] in
            guard let self, let converter = self.fromLive, !data.isEmpty else { return }
            let frames = AVAudioFrameCount(data.count / 2)
            guard let inBuffer = AVAudioPCMBuffer(pcmFormat: self.liveFormat, frameCapacity: frames) else { return }
            inBuffer.frameLength = frames
            data.withUnsafeBytes { raw in
                memcpy(inBuffer.int16ChannelData![0], raw.baseAddress!, Int(frames) * 2)
            }
            guard let out = Self.convert(inBuffer, with: converter) , let ch = out.floatChannelData else { return }
            self.ring.write(UnsafeBufferPointer(start: ch[0], count: Int(out.frameLength)))
        }
    }

    /// Drop anything not played yet (e.g. when a session closes).
    public func flushPlayback() { ring.clear() }

    // MARK: Capture

    private func captured(_ buffer: AVAudioPCMBuffer) {
        guard let mono = monoFormat, let channels = buffer.floatChannelData else { return }
        let frames = Int(buffer.frameLength)
        guard frames > 0, let monoBuffer = AVAudioPCMBuffer(pcmFormat: mono, frameCapacity: AVAudioFrameCount(frames)) else { return }
        monoBuffer.frameLength = AVAudioFrameCount(frames)
        // With voice processing every channel carries the same processed signal; take the first.
        memcpy(monoBuffer.floatChannelData![0], channels[0], frames * MemoryLayout<Float>.size)
        process(monoBuffer)
    }

    private func process(_ mono: AVAudioPCMBuffer) {
        let level = Self.level(UnsafeBufferPointer(start: mono.floatChannelData![0], count: Int(mono.frameLength)))
        levelLock.withLock { _inputLevel = level }
        guard let toLive, let toVAD,
              let live = Self.convert(mono, with: toLive),
              let vad = Self.convert(mono, with: toVAD)
        else { return }
        let pcm = Array(UnsafeBufferPointer(start: live.int16ChannelData![0], count: Int(live.frameLength)))
        let f16 = Array(UnsafeBufferPointer(start: vad.floatChannelData![0], count: Int(vad.frameLength)))
        onCapture?(pcm, f16)
    }

    private func startFeeder(_ urls: [URL]) throws {
        let files = try urls.map { try AVAudioFile(forReading: $0) }
        let mono48 = AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 1)!
        monoFormat = mono48
        toLive = AVAudioConverter(from: mono48, to: liveFormat)
        toVAD = AVAudioConverter(from: mono48, to: vadFormat)
        let chunk = AVAudioFrameCount(48_000 * 0.02)
        let thread = Thread { [weak self] in
            var queue = files
            var current: AVAudioFile?
            var converter: AVAudioConverter?
            var heardVoice = true   // the first file plays right away
            var quietSince: Date? = Date.distantPast
            while let self, self.running {
                let started = Date()
                var mono: AVAudioPCMBuffer?
                if current == nil, !queue.isEmpty {
                    let voice = self.outputLevel
                    if voice > 0.08 { heardVoice = true; quietSince = nil }
                    else if heardVoice { quietSince = quietSince ?? Date() }
                    if heardVoice, let since = quietSince, Date().timeIntervalSince(since) > 1.5 {
                        current = queue.removeFirst()
                        converter = AVAudioConverter(from: current!.processingFormat, to: mono48)
                        heardVoice = false
                        quietSince = nil
                    }
                }
                if let file = current {
                    let frames = AVAudioFrameCount(file.processingFormat.sampleRate * 0.02)
                    if let raw = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: frames) {
                        try? file.read(into: raw, frameCount: frames)
                        if raw.frameLength == 0 { current = nil } else if let converter { mono = Self.convert(raw, with: converter) }
                    }
                }
                if mono == nil, let silence = AVAudioPCMBuffer(pcmFormat: mono48, frameCapacity: chunk) {
                    silence.frameLength = chunk
                    memset(silence.floatChannelData![0], 0, Int(chunk) * MemoryLayout<Float>.size)
                    mono = silence
                }
                if let mono { self.queue.sync { self.process(mono) } }
                let wait = 0.02 - Date().timeIntervalSince(started)
                if wait > 0 { Thread.sleep(forTimeInterval: wait) }
            }
        }
        feeder = thread
        thread.start()
    }

    // MARK: Helpers

    static func convert(_ input: AVAudioPCMBuffer, with converter: AVAudioConverter) -> AVAudioPCMBuffer? {
        let ratio = converter.outputFormat.sampleRate / converter.inputFormat.sampleRate
        let capacity = AVAudioFrameCount(Double(input.frameLength) * ratio) + 64
        guard let output = AVAudioPCMBuffer(pcmFormat: converter.outputFormat, frameCapacity: capacity) else { return nil }
        var fed = false
        var error: NSError?
        let status = converter.convert(to: output, error: &error) { _, outStatus in
            if fed {
                outStatus.pointee = .noDataNow
                return nil
            }
            fed = true
            outStatus.pointee = .haveData
            return input
        }
        return status == .error ? nil : output
    }

    /// RMS on a decibel curve: -57 dBFS is silent, -13 dBFS is full.
    static func level(_ samples: UnsafeBufferPointer<Float>) -> Float {
        guard !samples.isEmpty else { return 0 }
        var sum: Float = 0
        for s in samples { sum += s * s }
        let rms = (sum / Float(samples.count)).squareRoot()
        guard rms > 0 else { return 0 }
        let db = 20 * log10(rms)
        return min(1, max(0, (db + 57) / 44))
    }

    public enum AudioError: Error { case noInput }
}
