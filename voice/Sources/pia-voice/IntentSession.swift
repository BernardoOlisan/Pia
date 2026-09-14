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
    var backendModel = "gpt-5.6-terra"
    /// Seconds without anyone speaking before the session closes (silence is billed).
    var idleSeconds: Double = 20
}

/// The intent conversation by voice. Runs on the main thread.
///
/// Local VAD hears speech → a GPT-Live session opens → the backend model takes notes through tools →
/// lines on stdout reach the Lead → the Lead writes rounds in intent.md → pia-voice notices them →
/// the voice asks them. Silence closes the session; a new round reopens it.
@MainActor
final class IntentSession {
    private enum State { case idle, connecting, live, closing }
    /// Output loudness (0...1 decibel curve) above which the voice is really making sound.
    private static let soundLevel: Float = 0.08

    private let options: Options
    private let emitter = Emitter()
    private var prompts: Prompts!
    private var apiKey = ""
    private var tools: IntentTools!
    private let audio = AudioIO()
    private let vad = VoiceActivity()
    private let transcript = Transcript()
    private var voiceLog: VoiceLog!
    private var cost = CostMeter()
    private let notch = NotchModel()
    private var notchWindow: NotchWindow?
    private let parentWatch = ParentWatch()
    private var intentPoller: FilePoller!

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
    private var noticedRound = 0
    private var noticedReady = false
    private var finishing = false
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

        let intentURL = options.workDir.appendingPathComponent("intent.md")
        tools = IntentTools(intentURL: intentURL) { [emitter] line in emitter.line(line) }
        let workID = options.workDir.lastPathComponent
        if let data = try? Data(contentsOf: options.workDir.appendingPathComponent("state.json")),
           let stateJSON = (try? JSONSerialization.jsonObject(with: data)) as? JSONObject {
            workTitle = stateJSON["title"] as? String ?? ""
        }
        voiceLog = VoiceLog(url: options.workDir.appendingPathComponent("logs/voice.md"), workID: workID)
        transcript.onTurn = { [weak self] turn in self?.voiceLog.turn(turn) }

        if options.showNotch {
            notch.onDotClick = { [weak self] in self?.end(reason: "dot clicked") }
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
        intentPoller = FilePoller(url: intentURL)
        intentPoller.start { [weak self] in self?.intentChanged() }
        Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }

        voiceLog.note("voice started (echo cancellation: \(audio.echoCancellation ? "on" : "off"))")
        emitter.line("PIA-VOICE READY " + JSON.encode(["work": workID, "echo_cancellation": audio.echoCancellation]))
        intentChanged()
    }

    /// Ends the voice before confirmation (click, signal, "no more voice", Claude closed).
    func end(reason: String, quiet: Bool = false) {
        guard !finishing else { return }
        finishing = true
        transcript.commit()
        if !tools.confirmed && !quiet { emitter.line(tools.endedLine(reason: reason)) }
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

        if state == .live {
            outgoing.append(contentsOf: pcm)
            if outgoing.count >= 960 { flushOutgoing() }
        } else if state == .idle, onset, !finishing {
            open(sendPreroll: true, notices: [])
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
        notch.level = max(audio.inputLevel, voiceLevel)
        notch.cost = cost.label
        transcript.flushPaused()

        if state == .live, !finishing, Date().timeIntervalSince(lastActivity) > options.idleSeconds {
            voiceLog.note("closing session after \(Int(options.idleSeconds))s of silence")
            closeSession()
        }
        if finishing == false, (tools?.confirmed == true || tools?.endRequested == true) {
            // Let the goodbye play, then leave.
            if !speaking, Date().timeIntervalSince(lastVoiceAudio) > 4 { finishAfterGoodbye() }
        }
    }

    // MARK: Sessions

    private func open(sendPreroll: Bool, notices: [JSONObject]) {
        state = .connecting
        sendPrerollOnStart = sendPreroll
        pendingOnStart = notices
        lastActivity = Date()
        let client = LiveClient(apiKey: apiKey)
        client.onEvent = { [weak self] event in MainActor.assumeIsolated { self?.handle(event) } }
        client.onClose = { [weak self] reason in MainActor.assumeIsolated { self?.socketClosed(reason) } }
        live = client
        client.connect()

        var config = LiveEvents.Config(instructions: voiceInstructions(), backendInstructions: backendInstructions(), tools: prompts.tools)
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
        cost.closeSession(finalSeconds: nil)
        live = nil
        state = .idle
        notch.connected = false
        outgoing.removeAll()
        audio.flushPlayback()
        transcript.commit()
    }

    private func handle(_ event: JSONObject) {
        guard let type = event["type"] as? String else { return }
        switch type {
        case "session.started":
            state = .live
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

        default:
            break
        }
    }

    private func runTool(_ call: LiveEvents.FunctionCall) {
        let output = tools.handle(name: call.name, arguments: call.arguments)
        voiceLog.note("tool \(call.name) \(call.arguments) → \(output)")
        live?.send(LiveEvents.functionOutput(callID: call.callID, output: output))
        live?.send(LiveEvents.responseCreate())
        lastVoiceAudio = Date()
    }

    private func finishAfterGoodbye() {
        guard !finishing else { return }
        finishing = true
        transcript.commit()
        if tools.endRequested && !tools.confirmed { emitter.line(tools.endedLine(reason: "human asked to stop voice")) }
        voiceLog.note(tools.confirmed ? "intent confirmed · \(cost.label)" : "voice ended by the human · \(cost.label)")
        shutdown()
    }

    // MARK: intent.md

    private func intentChanged() {
        guard let tools, !finishing else { return }
        let file = IntentFile.read(tools.intentURL)
        if file.readyToConfirm, !noticedReady {
            noticedReady = true
            notify(live: prompts.notice("ready_to_confirm"), reopen: prompts.notice("ready_reopen"))
            return
        }
        if let round = file.openRound(excluding: tools.roundsSent), round.number > noticedRound {
            noticedRound = round.number
            notify(live: prompts.notice("questions_ready", round: round.number, count: round.unansweredCount),
                   reopen: prompts.notice("questions_reopen", round: round.number, count: round.unansweredCount))
        }
    }

    /// In a live session: a silent notice. With no session: open one and have the voice speak first.
    private func notify(live text: String, reopen: String) {
        voiceLog.note("notice: \(text)")
        switch state {
        case .live:
            live?.send(LiveEvents.thinking(text))
        case .connecting:
            pendingOnStart.append(LiveEvents.thinking(text))
        case .idle, .closing:
            if state == .closing { live?.disconnect() }
            open(sendPreroll: false, notices: [LiveEvents.instructions(reopen)])
        }
    }

    // MARK: Prompts with context

    private func voiceInstructions() -> String {
        var text = prompts.voice
        if !workTitle.isEmpty { text += "\n\n# Este trabajo\n\(workTitle)" }
        if let intent = tools.lastIntent { text += "\n\n# Lo que ya se le mandó a Claude\n\(JSON.encode(intent))" }
        return text
    }

    private func backendInstructions() -> String {
        var text = prompts.backend
        if let intent = tools.lastIntent { text += "\n\n# Already sent to Claude\nIntent: \(JSON.encode(intent))" }
        if !tools.roundsSent.isEmpty { text += "\nAnswers already sent for rounds: \(tools.roundsSent.sorted().map(String.init).joined(separator: ", "))" }
        return text
    }
}
