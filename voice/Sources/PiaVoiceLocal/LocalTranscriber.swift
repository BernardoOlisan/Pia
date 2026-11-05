import FluidAudio
import Foundation

/// The fallback when OpenAI can't be reached: Parakeet TDT 0.6B v3 on this Mac's Neural Engine, through
/// FluidAudio. Multilingual (25 languages, Spanish among them), roughly 150× faster than real time on an
/// M-series Pro, no network once the model is on disk.
///
/// Not the main transcriber: it takes no prompt and no keywords, and it is weaker than gpt-transcribe
/// when Spanish and English are mixed in one take. It is there so a dictation without Wi-Fi still
/// lands in the clipboard instead of in `failed/`.
///
/// The model (~480 MB) is downloaded once, while online, into
/// `~/Library/Application Support/FluidAudio/Models/`. Offline, only what is already there is used.
public actor LocalTranscriber {
    public static let shared = LocalTranscriber()
    static let version = AsrModelVersion.v3

    private var manager: AsrManager?
    private var preparing: Task<AsrManager, Error>?
    private var downloading: Task<Void, Error>?

    public enum Failure: Error, CustomStringConvertible {
        case notDownloaded
        public var description: String {
            "the local model isn't downloaded yet (it downloads by itself the next time the Mac is online)"
        }
    }

    /// Whether the model is already on disk, so it can run with no network.
    public static var isDownloaded: Bool {
        AsrModels.modelsExist(at: AsrModels.defaultCacheDirectory(for: version), version: version)
    }

    public static var modelDirectory: URL { AsrModels.defaultCacheDirectory(for: version) }

    /// Download the model if it's missing, without loading it: called in the background when dictation
    /// starts, so the first take without network finds it on disk. Loading waits until a take needs it,
    /// so the model takes no memory while OpenAI is answering.
    public func ensureDownloaded() async throws {
        guard !Self.isDownloaded else { return }
        if let downloading { return try await downloading.value }
        let task = Task<Void, Error> { try await AsrModels.download(version: Self.version) }
        downloading = task
        defer { downloading = nil }
        try await task.value
    }

    /// Load the model from disk, once; later takes reuse it.
    private func load() async throws -> AsrManager {
        if let manager { return manager }
        if let preparing { return try await preparing.value }
        let task = Task<AsrManager, Error> {
            guard Self.isDownloaded else { throw Failure.notDownloaded }
            let models = try await AsrModels.loadFromCache(version: Self.version)
            let manager = AsrManager(config: .default)
            try await manager.loadModels(models)
            return manager
        }
        preparing = task
        defer { preparing = nil }
        let ready = try await task.value
        manager = ready
        return ready
    }

    /// Transcribe a recorded take. Never downloads: by the time this runs, the network has already failed.
    /// The first one after launch also loads the model (a few seconds).
    public func transcribe(_ audioFile: URL) async throws -> String {
        let manager = try await load()
        var state = TdtDecoderState.make(decoderLayers: await manager.decoderLayerCount)
        let result = try await manager.transcribe(audioFile, decoderState: &state)
        return result.text
    }
}
