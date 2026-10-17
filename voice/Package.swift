// swift-tools-version: 6.0
import PackageDescription

// PIA Voice: dictation from the notch (/pia:transcribe, ⌥Space), transcribed with gpt-transcribe.
// Build: swift build -c release --package-path voice
let package = Package(
    name: "pia-voice",
    platforms: [.macOS("26.0")],
    products: [
        .executable(name: "pia-voice", targets: ["pia-voice"]),
    ],
    targets: [
        // Transcription, the dictation buffer and ledger, keychain. No UI, no audio.
        .target(name: "PiaVoiceCore"),
        // The microphone and the recorder.
        .target(name: "PiaVoiceAudio"),
        // The notch island: shape, waveform, clock, cost.
        .target(name: "PiaVoiceNotch"),
        .executableTarget(name: "pia-voice", dependencies: ["PiaVoiceCore", "PiaVoiceAudio", "PiaVoiceNotch"]),
        .testTarget(name: "PiaVoiceCoreTests", dependencies: ["PiaVoiceCore"]),
    ],
    swiftLanguageModes: [.v5]
)
