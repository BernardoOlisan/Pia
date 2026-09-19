import XCTest
@testable import PiaVoiceCore

final class VoiceBridgeTests: XCTestCase {
    var dir: URL!
    var lines: [String] = []

    override func setUp() {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try! FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        lines = []
    }

    func bridge(mode: VoiceBridge.Mode = .speak) -> VoiceBridge {
        VoiceBridge(inbox: dir.appendingPathComponent("voice-inbox.txt"), mode: mode) { self.lines.append($0) }
    }

    func write(_ text: String) throws {
        try text.write(to: dir.appendingPathComponent("voice-inbox.txt"), atomically: true, encoding: .utf8)
    }

    func testOnlyNewLinesComeBack() throws {
        let b = bridge()
        XCTAssertEqual(b.newMessages(), [])
        try write("Primera.\n")
        XCTAssertEqual(b.newMessages(), ["Primera."])
        XCTAssertEqual(b.newMessages(), [], "the same message must never be said twice")
        try write("Primera.\nSegunda.\nTercera.\n")
        XCTAssertEqual(b.newMessages(), ["Segunda.", "Tercera."])
    }

    func testBlankLinesAreSeparatorsNotMessages() throws {
        let b = bridge()
        try write("\n\nUna.\n\n   \n\nOtra.\n")
        XCTAssertEqual(b.newMessages(), ["Una.", "Otra."])
    }

    func testAReplacedFileStartsOverInsteadOfRepeating() throws {
        let b = bridge()
        try write("Uno.\nDos.\nTres.\n")
        XCTAssertEqual(b.newMessages().count, 3)
        try write("Nuevo.\n")
        XCTAssertEqual(b.newMessages(), [], "shrinking resets the mark; it must not replay old lines")
        try write("Nuevo.\nOtro.\n")
        XCTAssertEqual(b.newMessages(), ["Otro."])
    }

    func testTellClaudeEmitsOneLine() {
        let out = JSON.decode(bridge().handle(name: "tell_claude", arguments: #"{"text":"quiere offline"}"#))!
        XCTAssertEqual(out["ok"] as? Bool, true)
        XCTAssertEqual(lines, [#"PIA-VOICE SAID {"text":"quiere offline"}"#])
    }

    func testTellClaudeNeedsText() {
        XCTAssertEqual(JSON.decode(bridge().handle(name: "tell_claude", arguments: #"{"text":"  "}"#))?["ok"] as? Bool, false)
        XCTAssertTrue(lines.isEmpty)
    }

    func testModeSwitchesBothWays() {
        let b = bridge()
        XCTAssertEqual(b.mode, .speak)
        XCTAssertEqual(JSON.decode(b.handle(name: "set_mode", arguments: #"{"mode":"notify"}"#))?["ok"] as? Bool, true)
        XCTAssertEqual(b.mode, .notify)
        XCTAssertEqual(lines.last, #"PIA-VOICE MODE {"mode":"notify"}"#)
        _ = b.handle(name: "set_mode", arguments: #"{"mode":"speak"}"#)
        XCTAssertEqual(b.mode, .speak)
        XCTAssertEqual(JSON.decode(b.handle(name: "set_mode", arguments: #"{"mode":"loud"}"#))?["ok"] as? Bool, false)
        XCTAssertEqual(b.mode, .speak)
    }

    func testEndVoiceKeepsTheReason() {
        let b = bridge()
        XCTAssertFalse(b.ended)
        _ = b.handle(name: "end_voice", arguments: #"{"reason":"ya no quiero hablar"}"#)
        XCTAssertTrue(b.ended)
        XCTAssertEqual(b.endReason, "ya no quiero hablar")
        XCTAssertEqual(b.endedLine(reason: b.endReason), #"PIA-VOICE ENDED {"reason":"ya no quiero hablar"}"#)
    }

    func testUnknownToolIsRefused() {
        XCTAssertEqual(JSON.decode(bridge().handle(name: "send_intent", arguments: "{}"))?["ok"] as? Bool, false)
    }
}

final class LiveEventsTests: XCTestCase {
    /// Tools belong to the delegation, never to the session. A session carrying `tools`/`tool_choice`
    /// is rejected outright with `Unknown parameter: 'session.tool_choice'`, and then the voice never
    /// opens at all — which is exactly what happened the one time this was built the other way.
    func testToolsLiveUnderDelegationAndNotOnTheSession() {
        var config = LiveEvents.Config(instructions: "voz", backendInstructions: "backend",
                                       tools: [["type": "function", "name": "tell_claude"]])
        config.voice = "marin"
        let event = LiveEvents.sessionStart(config, history: [LiveEvents.historyItem(role: "user", text: "hola")])
        XCTAssertEqual(event["type"] as? String, "session.start")
        let session = event["session"] as! JSONObject
        XCTAssertEqual(session["model"] as? String, "gpt-live-1")
        let audio = session["audio"] as! JSONObject
        XCTAssertEqual((audio["format"] as! JSONObject)["type"] as? String, "audio/pcm")
        XCTAssertEqual((audio["format"] as! JSONObject)["rate"] as? Int, 24_000)
        XCTAssertNil(session["tools"], "a session may not carry tools")
        XCTAssertNil(session["tool_choice"], "a session may not carry tool_choice")
        let delegation = session["delegation"] as! JSONObject
        XCTAssertEqual(delegation["type"] as? String, "responses")
        let responses = delegation["responses"] as! JSONObject
        XCTAssertEqual(responses["model"] as? String, "gpt-5.6-terra")
        XCTAssertEqual(responses["tool_choice"] as? String, "auto")
        let tools = responses["tools"] as! [JSONObject]
        XCTAssertEqual(tools.first?["name"] as? String, "tell_claude")
        XCTAssertEqual(tools.last?["type"] as? String, "web_search")
        XCTAssertEqual((session["input"] as! [JSONObject]).count, 1)
    }

    func testAppendsUseNullDelegation() {
        let text = JSON.encode(LiveEvents.thinking("aviso"))
        XCTAssertTrue(text.contains(#""delegation_id":null"#))
        XCTAssertTrue(text.contains(#""type":"session.thinking.append""#))
    }

    func testFunctionCallParsesTheWrappedShape() {
        let event = JSON.decode(#"{"type":"response.event","event_id":"e1","delegation_id":"d1","event":{"type":"response.output_item.done","item":{"type":"function_call","call_id":"call_1","name":"tell_claude","arguments":"{\"text\":\"x\"}"}}}"#)!
        XCTAssertEqual(LiveEvents.functionCall(in: event),
                       LiveEvents.FunctionCall(callID: "call_1", name: "tell_claude", arguments: #"{"text":"x"}"#))
    }

    /// Without a delegated model the session sends the event bare. Reading both shapes is what keeps a
    /// change at the other end from silently swallowing every tool call.
    func testFunctionCallParsesTheBareShape() {
        let event = JSON.decode(#"{"type":"response.output_item.done","item":{"type":"function_call","call_id":"call_2","name":"end_voice","arguments":"{\"reason\":\"ya\"}"}}"#)!
        XCTAssertEqual(LiveEvents.functionCall(in: event),
                       LiveEvents.FunctionCall(callID: "call_2", name: "end_voice", arguments: #"{"reason":"ya"}"#))
    }

    func testOtherEventsAreNotFunctionCalls() {
        XCTAssertNil(LiveEvents.functionCall(in: JSON.decode(#"{"type":"response.event","event":{"type":"response.output_text.delta"}}"#)!))
        XCTAssertNil(LiveEvents.functionCall(in: JSON.decode(#"{"type":"response.output_item.done","item":{"type":"message"}}"#)!))
    }
}

final class TranscriptAndCostTests: XCTestCase {
    func testTurnsAndHistory() {
        let t = Transcript()
        var logged: [String] = []
        t.onTurn = { logged.append($0.role) }
        let t0 = Date()
        t.user("Quiero ", at: t0); t.user(" un resumen", at: t0)
        // The voice starts a backchannel while the human is still talking: no split.
        t.assistant("¿Para ", at: t0.addingTimeInterval(0.5))
        t.flushPaused(now: t0.addingTimeInterval(1.5))
        XCTAssertEqual(t.turns.map(\.text), ["Quiero un resumen"])
        t.assistant("quién?", at: t0.addingTimeInterval(1.6))
        t.user("Para la app", at: t0.addingTimeInterval(3))
        t.commit()
        XCTAssertEqual(t.turns.map(\.text), ["Quiero un resumen", "¿Para quién?", "Para la app"])
        XCTAssertEqual(logged, ["user", "assistant", "user"])
        XCTAssertEqual(t.historyItems().count, 3)
        XCTAssertEqual(t.historyItems(maxTokens: 12).count, 1)
    }

    func testCostAddsUpSessions() {
        var cost = CostMeter()
        cost.update(sessionSeconds: 30)
        cost.update(sessionSeconds: 60)
        XCTAssertEqual(cost.label, "$0.05")
        cost.closeSession(finalSeconds: 66)
        cost.update(sessionSeconds: 54)
        XCTAssertEqual(cost.seconds, 120)
        XCTAssertEqual(cost.label, "$0.10")
    }

    func testNotices() {
        let n = Prompts.parseNotices("# Title\nignored\n## from_claude\nClaude dice: {text}\n\n## other\nx")
        let p = Prompts(voice: "", backend: "", tools: [], notices: n)
        XCTAssertEqual(p.notice("from_claude", text: "ya vi el caché"), "Claude dice: ya vi el caché")
        XCTAssertEqual(n["other"], "x")
    }
}
