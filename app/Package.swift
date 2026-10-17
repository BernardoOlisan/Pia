// swift-tools-version: 6.0
import PackageDescription

// PIA.app: the native half of PIA on macOS — notifications with the owl and its sounds, and PIA Awake
// (the Mac stays up with the lid closed while a work runs). Separate from voice/ so dictation is never
// touched by a change here.
// Build and bundle: scripts/pia-app.sh build
let package = Package(
    name: "pia-app",
    platforms: [.macOS("26.0")],
    products: [
        .executable(name: "PIA", targets: ["PIA"]),
    ],
    targets: [
        .target(name: "PiaAppCore"),
        .executableTarget(name: "PIA", dependencies: ["PiaAppCore"]),
        .testTarget(name: "PiaAppCoreTests", dependencies: ["PiaAppCore"]),
    ],
    swiftLanguageModes: [.v5]
)
