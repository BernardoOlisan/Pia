// swift-tools-version: 6.0
import PackageDescription

// PIA Voice: talk through a PIA intent with GPT-Live, from the notch.
// Build: swift build -c release --package-path voice
let package = Package(
    name: "pia-voice",
    platforms: [.macOS("26.0")],
    products: [
        .executable(name: "pia-voice", targets: ["pia-voice"]),
    ],
    dependencies: [
        // Only for Silero VAD (local voice activity detection).
        .package(url: "https://github.com/soniqo/speech-swift", exact: "0.0.23"),
    ],
    targets: [
        // GPT-Live protocol, tools, intent.md, bridge lines, cost, keychain. No UI, no audio.
        .target(name: "PiaVoiceCore"),
        // Microphone, speaker (with echo cancellation) and the local VAD.
        .target(name: "PiaVoiceAudio", dependencies: [
            .product(name: "SpeechVAD", package: "speech-swift"),
        ]),
        // The notch: shape, dot, cost, voice meter, speaking pulse.
        .target(name: "PiaVoiceNotch"),
        .executableTarget(name: "pia-voice", dependencies: ["PiaVoiceCore", "PiaVoiceAudio", "PiaVoiceNotch"]),
        .testTarget(name: "PiaVoiceCoreTests", dependencies: ["PiaVoiceCore"]),
    ],
    swiftLanguageModes: [.v5]
)
