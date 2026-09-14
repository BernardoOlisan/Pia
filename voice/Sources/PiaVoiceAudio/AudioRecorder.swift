import AVFoundation
import Foundation

/// Writes a dictation to an .m4a file (AAC, 24 kHz mono): about 360 KB a minute,
/// so an hour stays under the 25 MB transcription limit.
public final class AudioRecorder {
    public static let sampleRate = 24_000.0

    private var file: AVAudioFile?
    private let format = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: sampleRate, channels: 1, interleaved: true)!
    public private(set) var frames = 0

    public var seconds: Double { Double(frames) / Self.sampleRate }

    public init(url: URL) throws {
        try? FileManager.default.removeItem(at: url)
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: Self.sampleRate,
            AVNumberOfChannelsKey: 1,
            AVEncoderBitRateKey: 48_000,
        ]
        file = try AVAudioFile(forWriting: url, settings: settings, commonFormat: .pcmFormatInt16, interleaved: true)
    }

    /// 24 kHz PCM16, as `AudioIO.onCapture` delivers it.
    public func append(_ pcm: [Int16]) {
        guard let file, !pcm.isEmpty,
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(pcm.count))
        else { return }
        buffer.frameLength = AVAudioFrameCount(pcm.count)
        _ = pcm.withUnsafeBufferPointer { memcpy(buffer.int16ChannelData![0], $0.baseAddress!, pcm.count * 2) }
        do {
            try file.write(from: buffer)
            frames += pcm.count
        } catch {
            FileHandle.standardError.write("pia-voice: recorder: \(error)\n".data(using: .utf8)!)
        }
    }

    /// Closes the file so it can be read.
    public func finish() {
        file?.close()
        file = nil
    }
}
