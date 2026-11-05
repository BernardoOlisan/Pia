// swift-tools-version: 6.2
import PackageDescription

// PIA Voice: dictation from the notch (/pia:transcribe, ⌥Space), transcribed with gpt-transcribe,
// or locally with Parakeet when there is no network.
// Build: swift build -c release --package-path voice
let package = Package(
    name: "pia-voice",
    platforms: [.macOS("26.0")],
    products: [
        .executable(name: "pia-voice", targets: ["pia-voice"]),
    ],
    dependencies: [
        // Parakeet on the Neural Engine, for dictating with no network. Pinned, and with no traits:
        // only the speech recognition, not its text-to-speech or speaker diarization.
        .package(url: "https://github.com/FluidInference/FluidAudio", exact: "0.18.2", traits: []),
    ],
    targets: [
        // Transcription, the dictation buffer and ledger, keychain. No UI, no audio.
        .target(name: "PiaVoiceCore"),
        // The microphone and the recorder.
        .target(name: "PiaVoiceAudio"),
        // The notch island: shape, waveform, clock, cost.
        .target(name: "PiaVoiceNotch"),
        // The offline fallback: Parakeet, local, when OpenAI can't be reached.
        .target(name: "PiaVoiceLocal", dependencies: [.product(name: "FluidAudio", package: "FluidAudio")]),
        .executableTarget(name: "pia-voice", dependencies: ["PiaVoiceCore", "PiaVoiceAudio", "PiaVoiceNotch", "PiaVoiceLocal"]),
        .testTarget(name: "PiaVoiceCoreTests", dependencies: ["PiaVoiceCore"]),
    ],
    swiftLanguageModes: [.v5]
)
