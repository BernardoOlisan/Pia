import AppKit
import Foundation
import PiaVoiceAudio
import PiaVoiceCore
import PiaVoiceNotch

struct DictationOptions {
    /// Start recording as soon as it runs (the first `/pia:transcribe`).
    var recordNow = false
    /// That first take appends to what is already in the buffer instead of replacing it.
    var recordAppending = false
    var hotkey: HotkeySpec? = .default
    /// Keep running with no Claude Code open (manual testing).
    var stay = false
    /// A dictation stops by itself after this long.
    var maxSeconds: Double = 30 * 60
}

/// Where dictation keeps its files.
enum DictationPaths {
    static let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("PIA Voice")
    static let pid = dir.appendingPathComponent("dictate.pid")
    static let log = dir.appendingPathComponent("dictate.log")
    static let ledger = dir.appendingPathComponent("dictation.json")
    static let recording = dir.appendingPathComponent("recording.m4a")
    static let last = dir.appendingPathComponent("last.txt")
    /// Everything said since the last fresh take, so appending survives a restart of the daemon.
    static let buffer = dir.appendingPathComponent("buffer.txt")
    static let failed = dir.appendingPathComponent("failed")
}

/// Dictation, nothing else: record, transcribe with gpt-transcribe, put the text in the clipboard.
/// One process per Mac, alive while Claude Code is open. Toggled by the global shortcut, by `/pia:transcribe`
/// (SIGUSR1) or by clicking the island. Runs on the main thread.
@MainActor
final class DictationSession {
    private enum State { case idle, recording, transcribing }
    /// Shorter than this is a mis-press, not a dictation.
    private static let minimumSeconds = 0.6
    /// Microphone loudness (0...1 decibel curve) that only speech reaches; below it the recording is silence.
    private static let speechLevel: Float = 0.12

    private let options: DictationOptions
    private let model = DictationModel()
    private var window: NotchWindow!
    private var hotkey: GlobalHotkey?
    private var audio: AudioIO?
    private var recorder: AudioRecorder?
    private var ledger = DictationLedger.load(DictationPaths.ledger)
    private var state = State.idle
    private var started = Date()
    /// Whether the take being recorded now appends to the buffer or replaces it. Fixed when it starts,
    /// so stopping with either shortcut keeps the mode the take began with.
    private var appending = false
    private var loudest: Float = 0
    /// Bumped on every change of what the island shows, so a late hide never hides a newer phase.
    private var generation = 0
    private var quitWhenIdle = false
    private var claudeMissing = 0

    init(options: DictationOptions) {
        self.options = options
    }

    func start() {
        try? FileManager.default.createDirectory(at: DictationPaths.dir, withIntermediateDirectories: true)
        // One daemon per Mac, enforced by looking at the process table rather than trusting the PID file.
        let swept = DictationDaemon.sweepOthers()
        if swept > 0 { log("stopped \(swept) other dictation process\(swept == 1 ? "" : "es")") }
        DictationDaemon.writeRecord()
        window = NotchWindow(dictation: model)
        window.diagnostics = { [weak self] line in self?.log("island · " + line) }
        model.onTap = { [weak self] in
            guard let self, self.state == .recording else { return }
            self.stopRecording()
        }
        model.cost = DictationLedger.label(ledger.dollars())

        if let spec = options.hotkey {
            var bindings: [(spec: HotkeySpec, action: () -> Void)] = [
                (spec, { [weak self] in self?.toggle() }),
            ]
            if let appendSpec = spec.withShift {
                bindings.append((appendSpec, { [weak self] in self?.toggle(appendingTake: true) }))
            }
            hotkey = GlobalHotkey(bindings)
            if let hotkey {
                let taken = Set(hotkey.rejected.map(\.description))
                let ready = bindings.map(\.spec).filter { !taken.contains($0.description) }
                log("shortcut\(ready.count == 1 ? "" : "s") \(ready.map(\.description).joined(separator: " and ")) ready")
                for spec in hotkey.rejected { log("shortcut \(spec) could not be registered (another app may use it)") }
            } else {
                log("shortcuts could not be registered (another app may use them)")
            }
        }
        Timer.scheduledTimer(withTimeInterval: 1.0 / 20, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.watchClaude() }
        }
        log("ready (pid \(getpid()))")
        if options.recordNow { toggle(appendingTake: options.recordAppending) }
    }

    /// `appendingTake` only matters when a take starts: pressing either shortcut while recording stops it.
    func toggle(appendingTake: Bool = false) {
        switch state {
        case .idle: startRecording(appending: appendingTake)
        case .recording: stopRecording()
        case .transcribing: break
        }
    }

    /// Asked to exit (a newer build, or stopped): a dictation in progress finishes first, so nothing said is lost.
    func quit() {
        if state == .idle { exitNow() } else { quitWhenIdle = true }
    }

    // MARK: Recording

    private func startRecording(appending: Bool = false) {
        guard Secrets.openAIKey() != nil else {
            log("no OpenAI API key. Save it with: security add-generic-password -s pia-voice -a openai -w")
            finish(.failed)
            return
        }
        do {
            let recorder = try AudioRecorder(url: DictationPaths.recording)
            let audio = AudioIO()
            audio.onCapture = { [weak recorder] pcm, _ in
                DispatchQueue.main.async { recorder?.append(pcm) }
            }
            try audio.start(voiceProcessing: false)
            self.recorder = recorder
            self.audio = audio
        } catch {
            log("microphone could not start: \(error)")
            finish(.failed)
            return
        }
        state = .recording
        started = Date()
        loudest = 0
        self.appending = appending
        model.reset()
        model.appending = appending
        show(.recording)
        log(appending ? "recording (appending)" : "recording")
    }

    private func stopRecording() {
        guard state == .recording, let audio, let recorder else { return }
        audio.stop()
        self.audio = nil
        state = .transcribing
        model.level = 0
        // One more turn of the main queue, so the last captured chunks reach the file before it closes.
        DispatchQueue.main.async { [self] in
            recorder.finish()
            self.recorder = nil
            let seconds = recorder.seconds
            guard seconds >= Self.minimumSeconds, loudest >= Self.speechLevel else {
                log(String(format: "nothing heard (%.1fs, loudest %.2f)", seconds, loudest))
                state = .idle
                hide()
                return
            }
            show(.transcribing)
            Task { await self.transcribe(seconds: seconds) }
        }
    }

    private func transcribe(seconds: Double) async {
        guard let key = Secrets.openAIKey() else { finish(.failed); return }
        do {
            let result = try await Transcription.send(apiKey: key, audioFile: DictationPaths.recording)
            ledger.add(seconds: result.seconds ?? seconds)
            ledger.save(DictationPaths.ledger)
            model.cost = DictationLedger.label(ledger.dollars())
            let text = result.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else {
                log("empty transcript")
                finish(.failed)
                return
            }
            // An appending take carries everything said since the last fresh one, so one paste brings
            // the whole thought. A blank line between takes: you are stitching thoughts, not sentences.
            let clipboard = appending
                ? DictationBuffer.joined(previous: DictationBuffer.read(DictationPaths.buffer), take: text)
                : text
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(clipboard, forType: .string)
            try? clipboard.write(to: DictationPaths.buffer, atomically: true, encoding: .utf8)
            try? text.write(to: DictationPaths.last, atomically: true, encoding: .utf8)
            log(String(format: "copied %d characters%@ · %.0fs · this month %@",
                       clipboard.count, appending ? " (appended)" : "", seconds, model.cost))
            finish(.done)
        } catch {
            try? FileManager.default.createDirectory(at: DictationPaths.failed, withIntermediateDirectories: true)
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd-HHmmss"
            let kept = DictationPaths.failed.appendingPathComponent(formatter.string(from: Date()) + ".m4a")
            try? FileManager.default.moveItem(at: DictationPaths.recording, to: kept)
            log("transcription failed: \(error) · audio kept in \(kept.path)")
            finish(.failed)
        }
    }

    private func tick() {
        guard state == .recording, let audio else { return }
        let level = audio.inputLevel
        loudest = max(loudest, level)
        model.push(level: level)
        let elapsed = Date().timeIntervalSince(started)
        model.elapsed = elapsed
        let label = DictationLedger.label(ledger.dollars(pendingSeconds: elapsed))
        if model.cost != label { model.cost = label }
        if elapsed >= options.maxSeconds {
            log("longest dictation reached")
            stopRecording()
        }
    }

    // MARK: The island

    private func show(_ phase: DictationModel.Phase) {
        generation += 1
        let wasHidden = model.phase == .hidden
        window.show()
        if wasHidden {
            // The island has to draw once folded into the notch before it can unfold out of it.
            // One turn of the main queue is exactly that, and it doesn't guess at a duration.
            DispatchQueue.main.async { [weak self] in self?.model.phase = phase }
        } else {
            model.phase = phase
        }
    }

    /// The result stays a moment, then the island folds back into the notch.
    private func finish(_ phase: DictationModel.Phase) {
        state = .idle
        show(phase)
        let shown = generation
        DispatchQueue.main.asyncAfter(deadline: .now() + (phase == .done ? 1.4 : 2.6)) { [weak self] in
            guard let self, self.generation == shown else { return }
            self.hide()
        }
    }

    private func hide() {
        generation += 1
        let hidden = generation
        model.phase = .hidden
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            guard let self, self.generation == hidden else { return }
            self.window.hide()
            if self.quitWhenIdle && self.state == .idle { self.exitNow() }
        }
    }

    // MARK: Lifetime

    /// Exits when no Claude Code has been open for two checks in a row.
    private func watchClaude() {
        guard !options.stay, state == .idle else { return }
        claudeMissing = Self.claudeRunning() ? 0 : claudeMissing + 1
        if claudeMissing >= 2 {
            log("no Claude Code open; exiting")
            exitNow()
        }
    }

    private static func claudeRunning() -> Bool {
        let pgrep = Process()
        pgrep.executableURL = URL(fileURLWithPath: "/usr/bin/pgrep")
        pgrep.arguments = ["-x", "claude"]
        pgrep.standardOutput = FileHandle.nullDevice
        pgrep.standardError = FileHandle.nullDevice
        guard (try? pgrep.run()) != nil else { return true }
        pgrep.waitUntilExit()
        return pgrep.terminationStatus == 0
    }

    private func exitNow() {
        audio?.stop()
        window?.hide()
        DictationDaemon.removeRecord()
        log("exit")
        exit(0)
    }

    private func log(_ text: String) {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        FileHandle.standardError.write("\(formatter.string(from: Date())) · \(text)\n".data(using: .utf8)!)
    }
}
