import AppKit
import Foundation
import PiaVoiceAudio
import PiaVoiceCore
import PiaVoiceNotch

struct Options {
    var workDir: URL
    var promptsDir: String?
    /// Test mode: speech files played in turn, each after the voice finishes talking.
    var inputFiles: [URL] = []
    var showNotch = true
    var voice = "marin"
    /// Seconds without anyone speaking before the session closes (silence is billed).
    var idleSeconds: Double = 20
    /// What happens when Claude has something while the island is asleep.
    var mode = VoiceBridge.Mode.speak
    /// Wakes the island, or puts it back to sleep, without reaching for the mouse.
    var hotkey: HotkeySpec? = HotkeySpec.parse("option+v")
    /// The model that carries sentences to Claude. Tools only exist under delegation, so it has to be there.
    var backendModel = "gpt-5.6-terra"

}

/// The intent conversation by voice. Runs on the main thread.
///
/// Claude is the brain; this is his mouth and his ears. The voice passes on what you say with one
/// tool, Claude writes back a line at a time, and the voice says it in its own words.
///
/// The session costs money by the second, silence included, so it is awake only when it should be:
/// it opens when Claude first has something, closes itself after a stretch of quiet, and from then on
/// only a click or the shortcut wakes it. **Speaking never wakes it** — otherwise a cough near the
/// microphone starts billing.
@MainActor
final class IntentSession {
    private enum State { case idle, connecting, live, closing }
    /// Output loudness (0...1 decibel curve) above which the voice is really making sound.
    private static let soundLevel: Float = 0.08

    private let options: Options
    private let emitter = Emitter()
    private var prompts: Prompts!
    private var apiKey = ""
    private var bridge: VoiceBridge!
    private var hotkey: GlobalHotkey?
    /// What Claude said while the island was asleep, waiting for you to wake it.
    private var waiting: [String] = []
    private let audio = AudioIO()
    private let vad = VoiceActivity()
    private let transcript = Transcript()
    private var voiceLog: VoiceLog!
    private var cost = CostMeter()
    private let notch = NotchModel()
    private var notchWindow: NotchWindow?
    private let parentWatch = ParentWatch()
    private var inboxPoller: FilePoller!

    private var state = State.idle
    private var live: LiveClient?
    /// Appends to send right after `session.started`.
    private var pendingOnStart: [JSONObject] = []
    private var sendPrerollOnStart = false
    /// The last second of microphone audio, so the first words aren't lost while connecting.
    private var preroll: [Int16] = []
    private var outgoing: [Int16] = []
    private var lastActivity = Date()
    private var lastVoiceAudio = Date.distantPast
    private var finishing = false
    /// True once a session has opened at least once, so the first message always speaks whatever the mode.
    private var everOpened = false
    /// This attempt reached `session.started`. A socket that closes before that is a failure, not an end.
    private var reachedLive = false
    /// What the voice was about to say when the session failed, so it isn't lost.
    private var undelivered: [String] = []
    private var toldLeadAboutFailure = false
    private var workTitle = ""

    init(options: Options) {
        self.options = options
    }

    // MARK: Start and end

    func start() {
        guard let key = Secrets.openAIKey() else {
            fail("no OpenAI API key. Save it with: security add-generic-password -s pia-voice -a openai -w")
            return
        }
        apiKey = key
        guard let promptsURL = Prompts.locate(override: options.promptsDir) else { fail(Prompts.LoadError.notFound.description); return }
        do { prompts = try Prompts.load(dir: promptsURL) } catch { fail("\(error)"); return }

        let inboxURL = options.workDir.appendingPathComponent("logs/voice-inbox.txt")
        try? FileManager.default.createDirectory(at: inboxURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        if !FileManager.default.fileExists(atPath: inboxURL.path) {
            FileManager.default.createFile(atPath: inboxURL.path, contents: Data())
        }
        bridge = VoiceBridge(inbox: inboxURL, mode: options.mode) { [emitter] line in emitter.line(line) }
        let workID = options.workDir.lastPathComponent
        if let data = try? Data(contentsOf: options.workDir.appendingPathComponent("state.json")),
           let stateJSON = (try? JSONSerialization.jsonObject(with: data)) as? JSONObject {
            workTitle = stateJSON["title"] as? String ?? ""
        }
        voiceLog = VoiceLog(url: options.workDir.appendingPathComponent("logs/voice.md"), workID: workID)
        transcript.onTurn = { [weak self] turn in self?.voiceLog.turn(turn) }

        if options.showNotch {
            // One click is sleep/wake, not "end": ending is something you say. Two clicks stay the cost.
            notch.onDotClick = { [weak self] in self?.toggleAwake() }
            let window = NotchWindow(model: notch)
            window.show()
            notchWindow = window
        }

        audio.onCapture = { [weak self] pcm, f16 in
            DispatchQueue.main.async { self?.captured(pcm: pcm, f16: f16) }
        }
        do {
            try audio.start(inputFiles: options.inputFiles)
        } catch {
            fail("audio could not start: \(error)")
            return
        }
        Task { @MainActor in
            let engine = await vad.load()
            emitter.debug("vad: \(engine)")
        }

        parentWatch.start { [weak self] in
            MainActor.assumeIsolated { self?.end(reason: "Claude Code closed", quiet: true) }
        }
        if let spec = options.hotkey {
            hotkey = GlobalHotkey([(spec, { [weak self] in self?.toggleAwake() })])
            voiceLog.note(hotkey == nil ? "shortcut \(spec) could not be registered" : "shortcut \(spec) wakes and sleeps the island")
        }
        inboxPoller = FilePoller(url: inboxURL)
        inboxPoller.start { [weak self] in self?.inboxChanged() }
        Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }

        voiceLog.note("voice started (echo cancellation: \(audio.echoCancellation ? "on" : "off"))")
        emitter.line("PIA-VOICE READY " + JSON.encode([
            "work": workID, "echo_cancellation": audio.echoCancellation, "mode": options.mode.rawValue,
            "inbox": inboxURL.path,
        ]))
        inboxChanged()
    }

    /// Ends the voice before confirmation (click, signal, "no more voice", Claude closed).
    func end(reason: String, quiet: Bool = false) {
        guard !finishing else { return }
        finishing = true
        transcript.commit()
        if !quiet { emitter.line(bridge.endedLine(reason: reason)) }
        voiceLog.note("voice ended: \(reason) · \(cost.label)")
        shutdown()
    }

    private func fail(_ message: String) {
        emitter.line("PIA-VOICE ERROR " + JSON.encode(["message": message]))
        exit(2)
    }

    private func shutdown() {
        let exitNow = { [weak self] in
            self?.audio.stop()
            self?.notchWindow?.hide()
            exit(0)
        }
        if state == .live || state == .connecting {
            live?.send(LiveEvents.close())
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { exitNow() }
        } else {
            exitNow()
        }
    }

    // MARK: Audio

    private func captured(pcm: [Int16], f16: [Float]) {
        preroll.append(contentsOf: pcm)
        if preroll.count > LiveEvents.sampleRate { preroll.removeFirst(preroll.count - LiveEvents.sampleRate) }

        let onset = vad.feed(f16, level: audio.inputLevel)
        if vad.speaking { lastActivity = Date() }

        _ = onset
        // Asleep on purpose: speech is heard locally for the preroll and nothing else. Only a click,
        // the shortcut, or Claude in `speak` mode opens a session, so nothing you say can start billing.
        if state == .live {
            outgoing.append(contentsOf: pcm)
            if outgoing.count >= 960 { flushOutgoing() }
        }
    }

    private func flushOutgoing() {
        guard !outgoing.isEmpty else { return }
        let data = outgoing.withUnsafeBufferPointer { Data(buffer: $0) }
        live?.send(LiveEvents.audioAppend(base64: data.base64EncodedString()))
        outgoing.removeAll(keepingCapacity: true)
    }

    private func tick() {
        let voiceLevel = audio.outputLevel
        // GPT-Live streams audio all the time, silence included: only real sound counts as activity.
        let speaking = voiceLevel > Self.soundLevel
        if speaking { lastActivity = Date(); lastVoiceAudio = Date() }
        notch.voiceSpeaking = speaking
        notch.push(level: max(audio.inputLevel, voiceLevel))
        notch.elapsed = cost.seconds
        notch.cost = cost.label
        transcript.flushPaused()

        if state == .live, !finishing, Date().timeIntervalSince(lastActivity) > options.idleSeconds {
            voiceLog.note("closing session after \(Int(options.idleSeconds))s of silence")
            closeSession()
        }
        if finishing == false, bridge?.ended == true {
            // Let the goodbye play, then leave.
            if !speaking, Date().timeIntervalSince(lastVoiceAudio) > 4 { finishAfterGoodbye() }
        }
    }

    // MARK: Sessions

    private func open(sendPreroll: Bool, notices: [JSONObject]) {
        state = .connecting
        reachedLive = false
        sendPrerollOnStart = sendPreroll
        pendingOnStart = notices
        lastActivity = Date()
        let client = LiveClient(apiKey: apiKey)
        client.onEvent = { [weak self] event in MainActor.assumeIsolated { self?.handle(event) } }
        client.onClose = { [weak self] reason in MainActor.assumeIsolated { self?.socketClosed(reason) } }
        live = client
        client.connect()

        var config = LiveEvents.Config(instructions: voiceInstructions(),
                                       backendInstructions: prompts.backend, tools: prompts.tools)
        config.voice = options.voice
        config.backendModel = options.backendModel
        client.send(LiveEvents.sessionStart(config, history: transcript.historyItems()))
        voiceLog.note("session opening")
    }

    private func closeSession() {
        guard state == .live || state == .connecting else { return }
        state = .closing
        flushOutgoing()
        transcript.commit()
        live?.send(LiveEvents.close())
        DispatchQueue.main.asyncAfter(deadline: .now() + 4) { [weak self] in
            guard let self, self.state == .closing else { return }
            self.live?.disconnect()
        }
    }

    private func socketClosed(_ reason: String) {
        if state != .idle { emitter.debug("socket closed: \(reason)") }
        let failed = !reachedLive && state != .idle
        cost.closeSession(finalSeconds: nil)
        live = nil
        state = .idle
        notch.connected = false
        // A session that never opened is broken, not finished. Don't reopen on a timer: hold what the
        // voice was going to say, light the island, and let the human retry with a click.
        if failed {
            reportFailure(reason)
            if !undelivered.isEmpty {
                waiting.append(contentsOf: undelivered)
                undelivered = []
                notch.waiting = true
            }
        }
        outgoing.removeAll()
        audio.flushPlayback()
        transcript.commit()
    }

    private func handle(_ event: JSONObject) {
        guard let type = event["type"] as? String else { return }
        switch type {
        case "session.started":
            state = .live
            reachedLive = true
            everOpened = true
            undelivered = []
            notch.connected = true
            lastActivity = Date()
            if sendPrerollOnStart { outgoing = preroll; flushOutgoing() }
            for e in pendingOnStart { live?.send(e) }
            pendingOnStart = []
            voiceLog.note("session open")

        case "session.output_audio.delta":
            if let b64 = event["delta"] as? String, let data = Data(base64Encoded: b64) {
                audio.play(pcm16: data)
            }

        case "session.input_transcript.delta":
            if let d = event["delta"] as? String {
                transcript.user(d)
                if !d.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { lastActivity = Date() }
            }

        case "session.output_transcript.delta":
            if let d = event["delta"] as? String { transcript.assistant(d) }

        case "session.delegation.created", "session.thinking.appended", "session.instructions.appended":
            lastActivity = Date()

        case "response.event":
            lastActivity = Date()
            if let call = LiveEvents.functionCall(in: event) { runTool(call) }
            if let inner = event["event"] as? JSONObject, inner["type"] as? String == "response.completed",
               let usage = (inner["response"] as? JSONObject)?["usage"] as? JSONObject {
                cost.addBackend(inputTokens: usage["input_tokens"] as? Int ?? 0, outputTokens: usage["output_tokens"] as? Int ?? 0)
            }

        case "session.usage.updated":
            if let seconds = ((event["usage"] as? JSONObject)?["seconds"] as? NSNumber)?.doubleValue {
                cost.update(sessionSeconds: seconds)
            }

        case "session.closed":
            let seconds = ((event["usage"] as? JSONObject)?["seconds"] as? NSNumber)?.doubleValue
            cost.closeSession(finalSeconds: seconds)
            voiceLog.note("session closed (\(event["reason"] as? String ?? "?")) · \(cost.label) · backend tokens in \(cost.backendInputTokens) out \(cost.backendOutputTokens)")
            live?.disconnect()

        case "error":
            let error = event["error"] as? JSONObject ?? [:]
            let message = "\(error["code"] as? String ?? "error"): \(error["message"] as? String ?? "")"
            emitter.debug(message)
            voiceLog.note("error · \(message)")
            reportFailure(message)

        default:
            break
        }
    }

    private func runTool(_ call: LiveEvents.FunctionCall) {
        let output = bridge.handle(name: call.name, arguments: call.arguments)
        if call.name == "set_mode" { notch.notifyOnly = bridge.mode == .notify }
        voiceLog.note("tool \(call.name) \(call.arguments) → \(output)")
        live?.send(LiveEvents.functionOutput(callID: call.callID, output: output))
        live?.send(LiveEvents.responseCreate())
        lastVoiceAudio = Date()
    }

    private func finishAfterGoodbye() {
        guard !finishing else { return }
        finishing = true
        transcript.commit()
        emitter.line(bridge.endedLine(reason: bridge.endReason))
        voiceLog.note("voice ended: \(bridge.endReason) · \(cost.label)")
        shutdown()
    }

    // MARK: Claude's side of the conversation

    /// Claude appended to the inbox. Each line is something to say.
    private func inboxChanged() {
        guard let bridge, !finishing else { return }
        let messages = bridge.newMessages()
        guard !messages.isEmpty else { return }
        for message in messages { voiceLog.note("from claude: \(message)") }

        // The very first message always speaks: you just asked for a voice, so it answering is not a
        // surprise. After that the mode decides.
        let speakNow = !everOpened || bridge.mode == .speak
        guard speakNow else {
            waiting.append(contentsOf: messages)
            if !notch.waiting { chime() }
            notch.waiting = true
            voiceLog.note("holding \(waiting.count) message(s): notify mode")
            return
        }
        deliver(messages)
    }

    /// Says messages now, opening a session if there isn't one.
    private func deliver(_ messages: [String]) {
        let text = messages.joined(separator: "\n")
        notch.waiting = false
        waiting.removeAll()
        undelivered = messages
        switch state {
        case .live:
            live?.send(LiveEvents.thinking(prompts.notice("from_claude", text: text)))
            live?.send(LiveEvents.responseCreate())
        case .connecting:
            pendingOnStart.append(LiveEvents.thinking(prompts.notice("from_claude", text: text)))
        case .idle, .closing:
            if state == .closing { live?.disconnect() }
            open(sendPreroll: false, notices: [LiveEvents.instructions(prompts.notice("from_claude_reopen", text: text))])
        }
    }

    // MARK: Awake and asleep

    /// One click on the island, or the shortcut. Asleep → wake and deliver anything Claude is holding.
    /// Awake → sleep, and stop the meter.
    private func toggleAwake() {
        guard !finishing else { return }
        switch state {
        case .live, .connecting:
            voiceLog.note("asleep by hand · \(cost.label)")
            closeSession()
        case .idle, .closing:
            if !waiting.isEmpty {
                deliver(waiting)
            } else {
                notch.waiting = false
                if state == .closing { live?.disconnect() }
                open(sendPreroll: false, notices: [LiveEvents.instructions(prompts.notice("woken"))])
            }
        }
    }

    /// Tell the Lead the voice is broken. It used to go to stderr only, so Claude kept writing lines
    /// into an inbox nobody could read and the human just saw an island that never woke up.
    private func reportFailure(_ message: String) {
        guard !toldLeadAboutFailure, !finishing else { return }
        toldLeadAboutFailure = true
        emitter.line("PIA-VOICE ERROR " + JSON.encode([
            "message": message,
            "note": "the voice could not open a session; tell the human in one line and carry on in the terminal",
        ]))
    }

    /// One soft note, once, when Claude has something and the island stays quiet. Synthesised rather
    /// than a system sound, so it never reads as a notification.
    private func chime() {
        let rate = Double(LiveEvents.sampleRate)
        let seconds = 0.16
        let samples = Int(rate * seconds)
        var pcm = [Int16](repeating: 0, count: samples)
        for i in 0..<samples {
            let t = Double(i) / rate
            let envelope = exp(-t * 26) * (t < 0.006 ? t / 0.006 : 1)   // fast in, soft out: no click
            let tone = sin(2 * .pi * 880 * t) + 0.4 * sin(2 * .pi * 1320 * t)
            pcm[i] = Int16(max(-1, min(1, tone / 1.4)) * envelope * 5200)
        }
        audio.play(pcm16: pcm.withUnsafeBufferPointer { Data(buffer: $0) })
    }

    // MARK: Prompts with context

    private func voiceInstructions() -> String {
        var text = prompts.voice
        if !workTitle.isEmpty { text += "\n\n# Este trabajo\n\(workTitle)" }
        return text
    }
}
