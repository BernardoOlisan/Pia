import AppKit
import Foundation
import Network
import PiaVoiceAudio
import PiaVoiceCore
import PiaVoiceLocal
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
    /// Every take, audio and text, named by when it ended: `2026-11-05-093359.m4a` and `.txt`.
    /// About 360 KB per minute of speech. Deleting the folder loses nothing PIA needs.
    static let takes = dir.appendingPathComponent("takes")
    /// The global vocabulary, one term per line, sent with every take (see `Vocabulary`).
    static let vocabulary = dir.appendingPathComponent("vocabulary.txt")
    /// While this file exists every take behaves as if there were no network: cyan, transcribed locally.
    /// For trying the offline path while connected — `touch` it, dictate, `rm` it.
    static let forceOffline = dir.appendingPathComponent("offline")

    static func stamp(_ date: Date = Date()) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd-HHmmss"
        return formatter.string(from: date)
    }
}

/// Dictation, nothing else: record, transcribe with gpt-transcribe (or locally with Parakeet when OpenAI
/// can't be reached), put the text in the clipboard, and keep the take in `takes/`.
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
    /// Whether the Mac has a network path at all. Without one OpenAI isn't tried: the take goes straight
    /// to the local model, and the island is cyan while recording so you know.
    private let network = NWPathMonitor()
    private var online = true
    /// Fixed when a take starts: no network then (or `offline` forced), so it goes to the local model.
    private var takeOffline = false

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
        network.pathUpdateHandler = { [weak self] path in
            let online = path.status == .satisfied
            DispatchQueue.main.async { MainActor.assumeIsolated { self?.networkChanged(online: online) } }
        }
        network.start(queue: .global(qos: .utility))
        log("ready (pid \(getpid()))")
        prepareLocal()
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
        guard Secrets.openAIKey() != nil || LocalTranscriber.isDownloaded else {
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
        takeOffline = !online || FileManager.default.fileExists(atPath: DictationPaths.forceOffline.path)
        model.offline = takeOffline
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
        let audioFile = DictationPaths.recording
        var text: String?
        var engine = "gpt-transcribe"
        if !takeOffline, online, let key = Secrets.openAIKey() {
            do {
                let result = try await Transcription.send(apiKey: key, audioFile: audioFile, context: context(),
                                                          timeout: Transcription.timeout(forSeconds: seconds))
                ledger.add(seconds: result.seconds ?? seconds)
                ledger.save(DictationPaths.ledger)
                model.cost = DictationLedger.label(ledger.dollars())
                text = result.text
            } catch {
                log("transcription failed: \(String(describing: error).prefix(300)) · trying the local model")
            }
        }
        if text == nil {
            engine = "parakeet (local)"
            model.offline = true
            do {
                text = try await LocalTranscriber.shared.transcribe(audioFile)
            } catch {
                log("local transcription failed: \(error)")
            }
        }
        guard let text = text?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else {
            keepFailed()
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
        keepTake(text: text)
        log(String(format: "copied %d characters%@ · %.0fs · %@ · this month %@",
                   clipboard.count, appending ? " (appended)" : "", seconds, engine, model.cost))
        finish(.done)
    }

    private func networkChanged(online: Bool) {
        guard online != self.online else { return }
        self.online = online
        log(online ? "network back" : "no network · takes are transcribed on this Mac")
        if state == .recording, !online {
            takeOffline = true
            model.offline = true
        }
        if online { prepareLocal() }
    }

    /// The hints for this take: the global vocabulary, read again each time so an edit applies at once.
    private func context() -> Transcription.Context {
        var context = Transcription.Context()
        if let terms = Vocabulary.load(DictationPaths.vocabulary) {
            if terms.count > Vocabulary.limit {
                log("vocabulary has \(terms.count) terms; only the first \(Vocabulary.limit) are sent")
            }
            context.keywords = Array(terms.prefix(Vocabulary.limit))
        }
        return context
    }

    /// The take's audio and its own text (not the appended clipboard), side by side in `takes/`.
    private func keepTake(text: String) {
        let base = DictationPaths.takes.appendingPathComponent(DictationPaths.stamp())
        do {
            try FileManager.default.createDirectory(at: DictationPaths.takes, withIntermediateDirectories: true)
            try FileManager.default.copyItem(at: DictationPaths.recording, to: base.appendingPathExtension("m4a"))
            try text.write(to: base.appendingPathExtension("txt"), atomically: true, encoding: .utf8)
        } catch {
            log("take not kept: \(error)")
        }
    }

    /// Neither OpenAI nor the local model gave text: the audio is kept so nothing said is lost.
    private func keepFailed() {
        try? FileManager.default.createDirectory(at: DictationPaths.failed, withIntermediateDirectories: true)
        let kept = DictationPaths.failed.appendingPathComponent(DictationPaths.stamp() + ".m4a")
        try? FileManager.default.moveItem(at: DictationPaths.recording, to: kept)
        log("no transcript · audio kept in \(kept.path)")
    }

    /// Download Parakeet once, in the background, so a take without network finds it on disk.
    private func prepareLocal() {
        guard !LocalTranscriber.isDownloaded else { return }
        log("downloading the local model (~480 MB, once) into \(LocalTranscriber.modelDirectory.path)")
        Task.detached(priority: .utility) {
            do {
                try await LocalTranscriber.shared.ensureDownloaded()
                await MainActor.run { self.log("local model downloaded") }
            } catch {
                await MainActor.run { self.log("local model not downloaded (will try again next launch): \(error)") }
            }
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
