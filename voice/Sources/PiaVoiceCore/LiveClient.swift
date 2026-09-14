import Foundation

/// One GPT-Live WebSocket connection. Events are delivered on the main queue.
public final class LiveClient: NSObject, URLSessionWebSocketDelegate {
    public var onEvent: ((JSONObject) -> Void)?
    public var onOpen: (() -> Void)?
    /// Called once, when the socket closes or fails.
    public var onClose: ((String) -> Void)?

    private let apiKey: String
    private let url: URL
    private var session: URLSession?
    private var task: URLSessionWebSocketTask?
    private var closed = false

    public init(apiKey: String, url: URL = LiveEvents.url) {
        self.apiKey = apiKey
        self.url = url
    }

    public func connect() {
        var request = URLRequest(url: url)
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        let session = URLSession(configuration: .default, delegate: self, delegateQueue: nil)
        let task = session.webSocketTask(with: request)
        task.maximumMessageSize = 16 * 1024 * 1024
        self.session = session
        self.task = task
        task.resume()
        receive()
    }

    public func send(_ event: JSONObject) {
        guard let task, !closed else { return }
        task.send(.string(JSON.encode(event))) { [weak self] error in
            if let error { self?.finish("send failed: \(error.localizedDescription)") }
        }
    }

    public func disconnect() {
        task?.cancel(with: .normalClosure, reason: nil)
        finish("disconnected")
    }

    private func receive() {
        task?.receive { [weak self] result in
            guard let self else { return }
            switch result {
            case .success(let message):
                var text: String?
                switch message {
                case .string(let s): text = s
                case .data(let d): text = String(data: d, encoding: .utf8)
                @unknown default: break
                }
                if let text, let event = JSON.decode(text) {
                    DispatchQueue.main.async { self.onEvent?(event) }
                }
                self.receive()
            case .failure(let error):
                self.finish("socket: \(error.localizedDescription)")
            }
        }
    }

    private func finish(_ reason: String) {
        DispatchQueue.main.async {
            guard !self.closed else { return }
            self.closed = true
            self.session?.invalidateAndCancel()
            self.onClose?(reason)
        }
    }

    public func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didOpenWithProtocol protocol: String?) {
        DispatchQueue.main.async { self.onOpen?() }
    }

    public func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask,
                           didCloseWith closeCode: URLSessionWebSocketTask.CloseCode, reason: Data?) {
        let text = reason.flatMap { String(data: $0, encoding: .utf8) } ?? ""
        finish("closed (\(closeCode.rawValue)) \(text)")
    }

    public func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error { finish("failed: \(error.localizedDescription)") }
    }
}
