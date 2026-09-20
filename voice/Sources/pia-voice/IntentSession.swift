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
    var voice = "sol"
    /// Seconds without anyone speaking before the session closes (silence is billed).
    var idleSeconds: Double = 20
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
    /// What Claude said that the voice could not deliver, held until it can.
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
    /// When the open session started, so the clock ticks every frame instead of waiting for the server.
    private var sessionOpenedAt = Date()
    /// Loudness of the audio GPT-Live sent us, before it reaches the speakers. The speaker level moves
    /// with the Mac's volume; this doesn't, so the island breathes the same however loud you have it.
    private var voiceEnvelope: Float = 0
    private var gapsAtSessionStart = 0
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
        bridge = VoiceBridge(inbox: inboxURL) { [emitter] line in emitter.line(line) }
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
        Timer.scheduledTimer(withTimeInterval: 1.0 / 20, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }

        voiceLog.note("voice started (echo cancellation: \(audio.echoCancellation ? "on" : "off"))")
        emitter.line("PIA-VOICE READY " + JSON.encode([
            "work": workID, "echo_cancellation": audio.echoCancellation, "inbox": inboxURL.path,
        ]))
        // Say hello straight away. Claude still has to read the code, and a person would say so out
        // loud rather than leave you looking at a silent island for a minute.
        greet()
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
        // The voice's own loudness, decayed: the island breathes with what GPT-Live sent, not with how
        // loud your speakers happen to be.
        voiceEnvelope *= 0.82
        let speaking = state == .live && Date().timeIntervalSince(lastVoiceAudio) < 0.35 && voiceEnvelope > 0.02
        if speaking { lastActivity = Date() }
        notch.voiceSpeaking = speaking
        notch.level = speaking ? min(1, voiceEnvelope * 2.2) : 0
        // The waveform is your microphone and nothing else.
        notch.push(level: audio.inputLevel)
        // The clock runs locally between the server's cumulative reports, so it ticks instead of jumping.
        let openFor = state == .live ? Date().timeIntervalSince(sessionOpenedAt) : 0
        notch.elapsed = cost.closedSeconds + max(cost.sessionSeconds, openFor)
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
        gapsAtSessionStart = audio.playbackGaps
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
            sessionOpenedAt = Date()
            undelivered = []
            notch.connected = true
            lastActivity = Date()
            if sendPrerollOnStart { outgoing = preroll; flushOutgoing() }
            for e in pendingOnStart { live?.send(e) }
            pendingOnStart = []
            voiceLog.note("session open")

        case "session.output_audio.delta":
            if let b64 = event["delta"] as? String, let data = Data(base64Encoded: b64) {
                voiceEnvelope = max(voiceEnvelope, Self.loudness(of: data))
                lastVoiceAudio = Date()
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
            let gaps = audio.playbackGaps - gapsAtSessionStart
            voiceLog.note("session closed (\(event["reason"] as? String ?? "?")) · \(cost.breakdown)"
                          + (gaps > 0 ? " · \(gaps) audible gap\(gaps == 1 ? "" : "s") in playback" : ""))
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
        deliver(waiting + messages)
    }

    /// Says messages now, opening a session if there isn't one.
    ///
    /// Each message becomes its own append. A live session refuses anything over 500 tokens, and the
    /// one time they were glued together the whole of a deep research answer was rejected and never
    /// heard. Long ones are split on sentence boundaries rather than dropped.
    private func deliver(_ messages: [String]) {
        guard !messages.isEmpty else { return }
        notch.waiting = false
        waiting.removeAll()
        undelivered = messages

        let opening = state == .idle || state == .closing
        let key = opening ? "from_claude_reopen" : "from_claude"
        let events = Self.chunked(messages).map { piece in
            opening ? LiveEvents.instructions(prompts.notice(key, text: piece))
                    : LiveEvents.thinking(prompts.notice(key, text: piece))
        }
        deliverNotices(events, opening: opening)
    }

    private func deliverNotices(_ events: [JSONObject], opening: Bool) {
        switch state {
        case .live:
            for event in events { live?.send(event) }
            live?.send(LiveEvents.responseCreate())
        case .connecting:
            pendingOnStart.append(contentsOf: events)
        case .idle, .closing:
            if state == .closing { live?.disconnect() }
            open(sendPreroll: false, notices: events)
        }
        _ = opening
    }

    /// Roughly 500 tokens, measured as characters because that is all we can measure here and it errs
    /// on the safe side for Spanish. Split at sentence ends so a piece never stops mid-word.
    static let appendCharacterLimit = 1400

    static func chunked(_ messages: [String]) -> [String] {
        var pieces: [String] = []
        for message in messages {
            let text = message.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { continue }
            if text.count <= appendCharacterLimit { pieces.append(text); continue }
            var current = ""
            for sentence in text.split(separator: " ", omittingEmptySubsequences: false) {
                let candidate = current.isEmpty ? String(sentence) : current + " " + sentence
                if candidate.count > appendCharacterLimit, !current.isEmpty {
                    pieces.append(current)
                    current = String(sentence)
                } else {
                    current = candidate
                }
            }
            if !current.isEmpty { pieces.append(current) }
        }
        return pieces
    }

    /// 0...1 loudness of a block of 16-bit PCM, straight from GPT-Live.
    static func loudness(of data: Data) -> Float {
        guard data.count >= 2 else { return 0 }
        return data.withUnsafeBytes { raw -> Float in
            let samples = raw.bindMemory(to: Int16.self)
            guard !samples.isEmpty else { return 0 }
            var sum: Double = 0
            let step = max(1, samples.count / 512)
            var counted = 0
            var i = 0
            while i < samples.count {
                let value = Double(samples[i]) / 32768
                sum += value * value
                counted += 1
                i += step
            }
            guard counted > 0 else { return 0 }
            return Float(min(1, (sum / Double(counted)).squareRoot() * 3))
        }
    }

    /// The first thing that happens: a hello while Claude reads the code. A person would say "give me
    /// a second" out loud rather than leave you staring at a silent island.
    private func greet() {
        let intro = workTitle.isEmpty ? "(todavía no dijo el título del trabajo)" : workTitle
        deliverNotices([LiveEvents.instructions(prompts.notice("greeting", text: intro))], opening: true)
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

    // MARK: Awake and asleep

    /// One click on the island, or the shortcut. Asleep → wake and deliver anything held back.
    /// Awake → sleep, and stop the meter.
    private func toggleAwake() {
        guard !finishing else { return }
        switch state {
        case .live, .connecting:
            voiceLog.note("asleep by hand · \(cost.breakdown)")
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

    // MARK: Prompts with context

    private func voiceInstructions() -> String {
        var text = prompts.voice
        if !workTitle.isEmpty { text += "\n\n# Este trabajo\n\(workTitle)" }
        return text
    }
}
