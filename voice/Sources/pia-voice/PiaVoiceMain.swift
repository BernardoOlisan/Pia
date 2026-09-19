import AppKit
import Foundation
import PiaVoiceCore
import PiaVoiceNotch

@main
enum PiaVoiceMain {
    static let usage = """
    usage: pia-voice intent <work dir> [options]
           pia-voice dictate toggle|ensure|stop
           pia-voice dictate serve [--record] [--hotkey <keys>|off] [--stay]
           pia-voice transcribe <audio file>
           pia-voice notch demo [--voice] [--capsule|--notch] [--cycle]

    intent: talk through a PIA intent with GPT-Live. Prints PIA-VOICE lines for the Lead on stdout.

      --prompts <dir>        prompts folder (default: voice/prompts/intent next to the build)
      --input-file <audio>   test mode: speech from audio files instead of the microphone; repeat it
                             for several turns, each played after the voice stops talking
      --no-notch             don't show the notch
      --voice <name>         GPT-Live voice (default: marin)
      --backend-model <m>    Responses backend model (default: gpt-5.6-terra)
      --idle <seconds>       close the session after this much silence (default: 20)

    dictate: record, transcribe with gpt-transcribe, copy the text to the clipboard.

      toggle                 start or stop a dictation (starts the dictation process if needed)
      ensure                 make sure the dictation process runs, and is this build
      stop                   stop the dictation process
      serve                  the dictation process itself (started by toggle and ensure)
        --record             start recording right away
        --hotkey <keys>      global shortcut, e.g. option+space (default; also PIA_TRANSCRIBE_HOTKEY), or off
        --stay               keep running when no Claude Code is open

    transcribe: transcribe one audio file with gpt-transcribe and print the text (for testing).

    notch demo: the island with a fake voice — no microphone, no API key, nothing billed. For judging
    the shape, the motion and whether it follows you across Spaces and screens.

      --voice                the GPT-Live intent island instead of the dictation one
      --capsule / --notch    force the other screen's shape (an external monitor has no notch)
      --cycle                walk through the states on its own
      --quiet                no diagnostics on stderr
    """

    static func main() {
        var args = Array(CommandLine.arguments.dropFirst())
        let command = args.isEmpty ? "" : args.removeFirst()
        switch command {
        case "intent": runIntent(args)
        case "dictate": runDictate(args)
        case "transcribe": runTranscribe(args)
        case "notch": runNotch(args)
        case "--help", "-h": print(usage); exit(0)
        default: fail(usage)
        }
    }

    static func fail(_ message: String) -> Never {
        FileHandle.standardError.write((message + "\n").data(using: .utf8)!)
        exit(1)
    }

    // MARK: intent

    static func runIntent(_ arguments: [String]) {
        var args = arguments
        guard !args.isEmpty else { fail(usage) }
        var options = Options(workDir: URL(fileURLWithPath: args.removeFirst()).standardizedFileURL)
        while !args.isEmpty {
            let flag = args.removeFirst()
            func value() -> String {
                guard !args.isEmpty else { fail("missing value for \(flag)") }
                return args.removeFirst()
            }
            switch flag {
            case "--prompts": options.promptsDir = value()
            case "--input-file": options.inputFiles.append(URL(fileURLWithPath: value()))
            case "--no-notch": options.showNotch = false
            case "--voice": options.voice = value()
            case "--backend-model": options.backendModel = value()
            case "--idle": options.idleSeconds = Double(value()) ?? 20
            default: fail("unknown option \(flag)\n\(usage)")
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
            onSignals([SIGTERM, SIGINT, SIGHUP]) { session.end(reason: "stopped by the Lead") }
            DispatchQueue.main.async { MainActor.assumeIsolated { session.start() } }
            retained = session
        }
        app.run()
    }

    // MARK: dictate

    static func runDictate(_ arguments: [String]) {
        var args = arguments
        let action = args.isEmpty ? "" : args.removeFirst()
        switch action {
        case "toggle": exit(DictationDaemon.toggle())
        case "ensure": exit(DictationDaemon.ensure())
        case "stop": exit(DictationDaemon.stop())
        case "serve": break
        default: fail(usage)
        }

        var options = DictationOptions()
        var hotkeyText = ProcessInfo.processInfo.environment["PIA_TRANSCRIBE_HOTKEY"]
        while !args.isEmpty {
            let flag = args.removeFirst()
            switch flag {
            case "--record": options.recordNow = true
            case "--stay": options.stay = true
            case "--hotkey":
                guard !args.isEmpty else { fail("missing value for --hotkey") }
                hotkeyText = args.removeFirst()
            default: fail("unknown option \(flag)\n\(usage)")
            }
        }
        if let text = hotkeyText, !text.isEmpty {
            if text.lowercased() == "off" {
                options.hotkey = nil
            } else if let spec = HotkeySpec.parse(text) {
                options.hotkey = spec
            } else {
                FileHandle.standardError.write("pia-voice: shortcut \"\(text)\" not understood; using \(HotkeySpec.default)\n".data(using: .utf8)!)
            }
        }

        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        MainActor.assumeIsolated {
            let session = DictationSession(options: options)
            onSignals([SIGUSR1]) { session.toggle() }
            onSignals([SIGTERM, SIGINT, SIGHUP]) { session.quit() }
            DispatchQueue.main.async { MainActor.assumeIsolated { session.start() } }
            retained = session
        }
        app.run()
    }

    // MARK: transcribe

    static func runTranscribe(_ args: [String]) {
        guard let path = args.first else { fail(usage) }
        guard let key = Secrets.openAIKey() else { fail("no OpenAI API key. Save it with: security add-generic-password -s pia-voice -a openai -w") }
        let done = DispatchSemaphore(value: 0)
        var status: Int32 = 0
        Task {
            do {
                let result = try await Transcription.send(apiKey: key, audioFile: URL(fileURLWithPath: path))
                print(result.text)
                if let seconds = result.seconds {
                    FileHandle.standardError.write("\(seconds)s · \(DictationLedger.label(seconds / 60 * Transcription.dollarsPerMinute))\n".data(using: .utf8)!)
                }
            } catch {
                FileHandle.standardError.write("pia-voice: \(error)\n".data(using: .utf8)!)
                status = 2
            }
            done.signal()
        }
        done.wait()
        exit(status)
    }

    // MARK: notch demo

    static func runNotch(_ arguments: [String]) {
        var args = arguments
        guard !args.isEmpty, args.removeFirst() == "demo" else { fail(usage) }
        var options = NotchDemoOptions()
        while !args.isEmpty {
            switch args.removeFirst() {
            case "--voice": options.island = "voice"
            case "--dictation": options.island = "dictation"
            case "--capsule": options.forcedStyle = .capsule
            case "--notch": options.forcedStyle = .notch
            case "--cycle": options.cycle = true
            case "--quiet": options.quiet = true
            case let flag: fail("unknown option \(flag)\n\(usage)")
            }
        }
        setvbuf(stdout, nil, _IOLBF, 0)
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        MainActor.assumeIsolated {
            let demo = NotchDemo(options: options)
            onSignals([SIGTERM, SIGINT, SIGHUP]) { exit(0) }
            DispatchQueue.main.async { MainActor.assumeIsolated { demo.start() } }
            retained = demo
        }
        app.run()
    }

    // MARK: Signals

    @MainActor
    static func onSignals(_ signals: [Int32], _ handler: @escaping @MainActor () -> Void) {
        for sig in signals {
            signal(sig, SIG_IGN)
            let source = DispatchSource.makeSignalSource(signal: sig, queue: .main)
            source.setEventHandler { MainActor.assumeIsolated { handler() } }
            source.resume()
            signalSources.append(source)
        }
    }

    nonisolated(unsafe) static var signalSources: [DispatchSourceSignal] = []
    nonisolated(unsafe) static var retained: AnyObject?
}
