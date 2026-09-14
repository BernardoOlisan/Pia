import Foundation

/// The backend model's function tools for the intent conversation.
/// Each call returns the JSON text given back to the model as `function_call_output`.
public final class IntentTools {
    public let intentURL: URL
    private let emit: (String) -> Void

    public private(set) var lastIntent: JSONObject?
    public private(set) var answersSent: [Int: [Any]] = [:]
    public private(set) var confirmed = false
    public private(set) var endRequested = false

    public init(intentURL: URL, emit: @escaping (String) -> Void) {
        self.intentURL = intentURL
        self.emit = emit
    }

    public var roundsSent: Set<Int> { Set(answersSent.keys) }

    public func handle(name: String, arguments: String) -> String {
        let args = JSON.decode(arguments) ?? [:]
        switch name {
        case "send_intent":
            var intent: JSONObject = [:]
            for key in ["intention", "why", "done_looks_like", "in_scope", "out_of_scope", "constraints"] {
                if let value = args[key] as? String, !value.isEmpty { intent[key] = value }
            }
            guard intent["intention"] != nil else { return result(["ok": false, "error": "intention is required"]) }
            lastIntent = intent
            emit("PIA-VOICE INTENT " + JSON.encode(intent))
            return result(["ok": true, "note": "Claude received it and is reading the code to prepare questions. That can take a minute or two; keep talking with the human meanwhile."])

        case "check_questions":
            let state = IntentFile.read(intentURL)
            if state.readyToConfirm {
                return result(["status": "ready_to_confirm", "summary": state.summary])
            }
            if let round = state.openRound(excluding: roundsSent) {
                return result(["status": "questions", "round": round.number,
                               "question_count": round.unansweredCount, "questions": round.text])
            }
            return result(["status": "not_yet", "note": "Claude is still preparing questions."])

        case "send_answers":
            guard let round = (args["round"] as? NSNumber)?.intValue,
                  let answers = args["answers"] as? [Any], !answers.isEmpty
            else { return result(["ok": false, "error": "round and answers are required"]) }
            answersSent[round] = answers
            emit("PIA-VOICE ANSWERS R\(round) " + JSON.encode(["round": round, "answers": answers]))
            return result(["ok": true, "note": "Claude received the answers. It may send another round, or finish the intent."])

        case "confirm_intent":
            confirmed = true
            emit("PIA-VOICE CONFIRMED")
            return result(["ok": true, "note": "Say goodbye in one short sentence. Claude starts the research now."])

        case "end_voice":
            endRequested = true
            return result(["ok": true, "note": "Say goodbye in one short sentence. Claude continues in the terminal."])

        default:
            return result(["ok": false, "error": "unknown tool \(name)"])
        }
    }

    /// The line printed when the voice ends before confirmation, so the Lead continues from here.
    public func endedLine(reason: String) -> String {
        var payload: JSONObject = ["reason": reason]
        if let lastIntent { payload["intent"] = lastIntent }
        if !answersSent.isEmpty {
            payload["answers"] = answersSent.keys.sorted().map { ["round": $0, "answers": answersSent[$0]!] as JSONObject }
        }
        return "PIA-VOICE ENDED " + JSON.encode(payload)
    }

    private func result(_ object: JSONObject) -> String { JSON.encode(object) }
}
