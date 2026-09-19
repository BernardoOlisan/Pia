import Foundation

/// Client events for a GPT-Live primary WebSocket.
/// Shapes follow the OpenAI SDK types (`openai.types.live`).
public enum LiveEvents {
    public static let url = URL(string: "wss://api.openai.com/v1/live/sessions")!
    public static let sampleRate = 24_000

    public struct Config {
        public var model = "gpt-live-1"
        public var voice = "marin"
        public var instructions: String
        public var backendModel = "gpt-5.6-terra"
        public var backendInstructions: String
        public var tools: [JSONObject]
        public var reasoningEffort: String? = "low"

        public init(instructions: String, backendInstructions: String, tools: [JSONObject]) {
            self.instructions = instructions
            self.backendInstructions = backendInstructions
            self.tools = tools
        }
    }

    public static func newEventID() -> String {
        "pv_" + UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(16).lowercased()
    }

    /// Tools only exist under `delegation.responses`: a GPT-Live session cannot carry its own, and a
    /// session that tries is rejected outright (`Unknown parameter: 'session.tool_choice'`). So there
    /// is a model behind the voice, and there has to be — but its whole job is now to pass sentences
    /// to Claude, who is the one that thinks.
    public static func sessionStart(_ config: Config, history: [JSONObject]) -> JSONObject {
        var responses: JSONObject = [
            "model": config.backendModel,
            "instructions": config.backendInstructions,
            "tools": config.tools + [["type": "web_search"]],
            "tool_choice": "auto",
            "parallel_tool_calls": false,
        ]
        if let effort = config.reasoningEffort { responses["reasoning"] = ["effort": effort] }
        var session: JSONObject = [
            "model": config.model,
            "instructions": config.instructions,
            "audio": [
                "format": ["type": "audio/pcm", "rate": sampleRate],
                "output": ["voice": config.voice],
            ],
            "delegation": ["type": "responses", "responses": responses],
            "store": false,
        ]
        if !history.isEmpty { session["input"] = history }
        return ["type": "session.start", "event_id": newEventID(), "session": session]
    }

    public static func audioAppend(base64 audio: String) -> JSONObject {
        ["type": "session.input_audio.append", "audio": audio]
    }

    /// Silent context: known by the voice, not spoken right away.
    public static func thinking(_ content: String) -> JSONObject {
        ["type": "session.thinking.append", "event_id": newEventID(), "delegation_id": NSNull(), "content": content]
    }

    /// Something the voice should say, in its own words.
    public static func commentary(_ content: String) -> JSONObject {
        ["type": "session.commentary.append", "event_id": newEventID(), "delegation_id": NSNull(), "content": content]
    }

    public static func instructions(_ content: String) -> JSONObject {
        ["type": "session.instructions.append", "event_id": newEventID(), "delegation_id": NSNull(), "content": content]
    }

    public static func functionOutput(callID: String, output: String) -> JSONObject {
        ["type": "response.item.create", "event_id": newEventID(),
         "item": ["type": "function_call_output", "call_id": callID, "output": output]]
    }

    public static func responseCreate() -> JSONObject {
        ["type": "response.create", "event_id": newEventID()]
    }

    public static func close() -> JSONObject {
        ["type": "session.close", "event_id": newEventID()]
    }

    /// One text history message for `session.start.input`.
    public static func historyItem(role: String, text: String) -> JSONObject {
        let partType = role == "assistant" ? "output_text" : "input_text"
        return ["type": "message", "role": role, "content": [["type": partType, "text": text]]]
    }

    /// A function call found inside a `response.event` server event, if any.
    public struct FunctionCall: Equatable {
        public let callID: String
        public let name: String
        public let arguments: String
    }

    /// Accepts both shapes: the bare `response.output_item.done` the session sends when it owns its
    /// tools, and the same event wrapped in `response.event`, which is how it arrived when a delegated
    /// model owned them. Reading both means a change at the other end can't silently swallow a call.
    public static func functionCall(in event: JSONObject) -> FunctionCall? {
        let item: JSONObject
        switch event["type"] as? String {
        case "response.output_item.done":
            guard let value = event["item"] as? JSONObject else { return nil }
            item = value
        case "response.event":
            guard let inner = event["event"] as? JSONObject,
                  inner["type"] as? String == "response.output_item.done",
                  let value = inner["item"] as? JSONObject
            else { return nil }
            item = value
        default:
            return nil
        }
        guard item["type"] as? String == "function_call",
              let callID = item["call_id"] as? String,
              let name = item["name"] as? String
        else { return nil }
        return FunctionCall(callID: callID, name: name, arguments: item["arguments"] as? String ?? "{}")
    }
}
