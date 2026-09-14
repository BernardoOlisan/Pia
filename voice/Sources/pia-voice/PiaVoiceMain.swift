import AppKit
import Foundation

@main
enum PiaVoiceMain {
    static let usage = """
    usage: pia-voice intent <work dir> [options]

      Talk through a PIA intent with GPT-Live. Prints PIA-VOICE lines for the Lead on stdout.

    options:
      --prompts <dir>        prompts folder (default: voice/prompts/intent next to the build)
      --input-file <audio>   test mode: speech from audio files instead of the microphone; repeat it
                             for several turns, each played after the voice stops talking
      --no-notch             don't show the notch
      --voice <name>         GPT-Live voice (default: marin)
      --backend-model <m>    Responses backend model (default: gpt-5.6-terra)
      --idle <seconds>       close the session after this much silence (default: 20)
    """

    static func main() {
        var args = Array(CommandLine.arguments.dropFirst())
        guard args.first == "intent", args.count >= 2 else {
            FileHandle.standardError.write((usage + "\n").data(using: .utf8)!)
            exit(args.first == "--help" || args.first == "-h" ? 0 : 1)
        }
        args.removeFirst()
        var options = Options(workDir: URL(fileURLWithPath: args.removeFirst()).standardizedFileURL)
        while !args.isEmpty {
            let flag = args.removeFirst()
            func value() -> String {
                guard !args.isEmpty else { FileHandle.standardError.write("missing value for \(flag)\n".data(using: .utf8)!); exit(1) }
                return args.removeFirst()
            }
            switch flag {
            case "--prompts": options.promptsDir = value()
            case "--input-file": options.inputFiles.append(URL(fileURLWithPath: value()))
            case "--no-notch": options.showNotch = false
            case "--voice": options.voice = value()
            case "--backend-model": options.backendModel = value()
            case "--idle": options.idleSeconds = Double(value()) ?? 20
            default:
                FileHandle.standardError.write("unknown option \(flag)\n\(usage)\n".data(using: .utf8)!)
                exit(1)
            }
        }
        guard FileManager.default.fileExists(atPath: options.workDir.path) else {
            print("PIA-VOICE ERROR {\"message\":\"work folder not found: \(options.workDir.path)\"}")
            exit(2)
        }

        setvbuf(stdout, nil, _IOLBF, 0)
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)

        MainActor.assumeIsolated {
            let session = IntentSession(options: options)
            for sig in [SIGTERM, SIGINT, SIGHUP] {
                signal(sig, SIG_IGN)
                let source = DispatchSource.makeSignalSource(signal: sig, queue: .main)
                source.setEventHandler { MainActor.assumeIsolated { session.end(reason: "stopped by the Lead") } }
                source.resume()
                signalSources.append(source)
            }
            DispatchQueue.main.async { MainActor.assumeIsolated { session.start() } }
            retained = session
        }
        app.run()
    }

    nonisolated(unsafe) static var signalSources: [DispatchSourceSignal] = []
    nonisolated(unsafe) static var retained: AnyObject?
}
