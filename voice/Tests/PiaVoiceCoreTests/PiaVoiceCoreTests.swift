import XCTest
@testable import PiaVoiceCore

final class IntentFileTests: XCTestCase {
    let sample = """
    # Weekly summary

    **Intention:** People see a weekly summary.

    ## Decided by the human
    - Spanish messages (question 4)

    ## Clarifications

    ### Round 1
    1. Who sees it? → The app decides.
    2. Which week? → Last 7 days.

    ### Round 2: follow-up
    1. Streak before today? *Suggested: keep it as is.*
    2. Compare weeks? *Suggested: no.*
    """

    func testRoundsAndAnswers() {
        let state = IntentFile.parse(sample)
        XCTAssertEqual(state.rounds.map(\.number), [1, 2])
        XCTAssertEqual(state.rounds[0].unansweredCount, 0)
        XCTAssertEqual(state.rounds[1].questionCount, 2)
        XCTAssertEqual(state.rounds[1].unansweredCount, 2)
        XCTAssertEqual(state.openRound()?.number, 2)
        XCTAssertNil(state.openRound(excluding: [2]))
        XCTAssertFalse(state.readyToConfirm)
        XCTAssertTrue(state.summary.contains("People see a weekly summary."))
        XCTAssertFalse(state.summary.contains("Decided by the human"))
    }

    func testReadyMarker() {
        let state = IntentFile.parse(IntentFile.readyMarker + "\n" + sample)
        XCTAssertTrue(state.readyToConfirm)
        XCTAssertFalse(state.summary.contains("pia-voice"))
    }
}

final class IntentToolsTests: XCTestCase {
    var dir: URL!
    var lines: [String] = []

    override func setUp() {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try! FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        lines = []
    }

    func tools() -> IntentTools {
        IntentTools(intentURL: dir.appendingPathComponent("intent.md")) { self.lines.append($0) }
    }

    func testSendIntentEmitsLine() {
        let t = tools()
        let out = JSON.decode(t.handle(name: "send_intent", arguments: #"{"intention":"Resumen semanal","why":"motivar"}"#))!
        XCTAssertEqual(out["ok"] as? Bool, true)
        XCTAssertEqual(lines, [#"PIA-VOICE INTENT {"intention":"Resumen semanal","why":"motivar"}"#])
    }

    func testSendIntentRequiresIntention() {
        let out = JSON.decode(tools().handle(name: "send_intent", arguments: "{}"))!
        XCTAssertEqual(out["ok"] as? Bool, false)
        XCTAssertTrue(lines.isEmpty)
    }

    func testCheckQuestionsFlow() throws {
        let t = tools()
        let url = dir.appendingPathComponent("intent.md")
        XCTAssertEqual(JSON.decode(t.handle(name: "check_questions", arguments: "{}"))?["status"] as? String, "not_yet")

        try "## Clarifications\n\n### Round 1\n1. Who sees it? *Suggested: the app.*\n".write(to: url, atomically: true, encoding: .utf8)
        let q = JSON.decode(t.handle(name: "check_questions", arguments: "{}"))!
        XCTAssertEqual(q["status"] as? String, "questions")
        XCTAssertEqual(q["round"] as? Int, 1)

        _ = t.handle(name: "send_answers", arguments: #"{"round":1,"answers":[{"question_number":1,"answer":"la app","decided_by_human":false}]}"#)
        XCTAssertTrue(lines.last!.hasPrefix("PIA-VOICE ANSWERS R1 "))
        XCTAssertEqual(JSON.decode(t.handle(name: "check_questions", arguments: "{}"))?["status"] as? String, "not_yet")

        try (IntentFile.readyMarker + "\n**Intention:** x\n").write(to: url, atomically: true, encoding: .utf8)
        let ready = JSON.decode(t.handle(name: "check_questions", arguments: "{}"))!
        XCTAssertEqual(ready["status"] as? String, "ready_to_confirm")
        XCTAssertEqual(ready["summary"] as? String, "**Intention:** x")
    }

    func testConfirmAndEnded() {
        let t = tools()
        _ = t.handle(name: "send_intent", arguments: #"{"intention":"x"}"#)
        XCTAssertEqual(t.endedLine(reason: "click"), #"PIA-VOICE ENDED {"intent":{"intention":"x"},"reason":"click"}"#)
        _ = t.handle(name: "confirm_intent", arguments: "{}")
        XCTAssertTrue(t.confirmed)
        XCTAssertEqual(lines.last, "PIA-VOICE CONFIRMED")
    }
}

final class LiveEventsTests: XCTestCase {
    func testSessionStartShape() {
        var config = LiveEvents.Config(instructions: "voz", backendInstructions: "backend",
                                       tools: [["type": "function", "name": "check_questions"]])
        config.voice = "marin"
        let event = LiveEvents.sessionStart(config, history: [LiveEvents.historyItem(role: "user", text: "hola")])
        XCTAssertEqual(event["type"] as? String, "session.start")
        let session = event["session"] as! JSONObject
        XCTAssertEqual(session["model"] as? String, "gpt-live-1")
        let audio = session["audio"] as! JSONObject
        XCTAssertEqual((audio["format"] as! JSONObject)["type"] as? String, "audio/pcm")
        XCTAssertEqual((audio["format"] as! JSONObject)["rate"] as? Int, 24_000)
        let delegation = session["delegation"] as! JSONObject
        XCTAssertEqual(delegation["type"] as? String, "responses")
        let tools = (delegation["responses"] as! JSONObject)["tools"] as! [JSONObject]
        XCTAssertEqual(tools.last?["type"] as? String, "web_search")
        XCTAssertEqual((session["input"] as! [JSONObject]).count, 1)
    }

    func testAppendsUseNullDelegation() {
        let text = JSON.encode(LiveEvents.thinking("aviso"))
        XCTAssertTrue(text.contains(#""delegation_id":null"#))
        XCTAssertTrue(text.contains(#""type":"session.thinking.append""#))
    }

    func testFunctionCallParsing() {
        let event = JSON.decode(#"{"type":"response.event","event_id":"e1","delegation_id":"d1","event":{"type":"response.output_item.done","item":{"type":"function_call","call_id":"call_1","name":"send_intent","arguments":"{\"intention\":\"x\"}"}}}"#)!
        XCTAssertEqual(LiveEvents.functionCall(in: event),
                       LiveEvents.FunctionCall(callID: "call_1", name: "send_intent", arguments: #"{"intention":"x"}"#))
        let other = JSON.decode(#"{"type":"response.event","event":{"type":"response.output_text.delta"}}"#)!
        XCTAssertNil(LiveEvents.functionCall(in: other))
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
        let n = Prompts.parseNotices("# Title\nignored\n## questions_ready\nRonda {round}, {count} preguntas.\n\n## other\nx")
        let p = Prompts(voice: "", backend: "", tools: [], notices: n)
        XCTAssertEqual(p.notice("questions_ready", round: 2, count: 3), "Ronda 2, 3 preguntas.")
        XCTAssertEqual(n["other"], "x")
    }
}
