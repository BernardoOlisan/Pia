import Foundation

/// `logs/voice.md`: the full conversation, so nothing said by voice is lost.
public final class VoiceLog {
    private let url: URL
    private let formatter: DateFormatter

    public init(url: URL, workID: String) {
        self.url = url
        formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        let fm = FileManager.default
        try? fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        if !fm.fileExists(atPath: url.path) {
            let header = "# Log: voice · work \(workID)\n\nThe intent conversation by voice, written by pia-voice.\n\n## Entries\n"
            try? header.write(to: url, atomically: true, encoding: .utf8)
        }
    }

    public func turn(_ turn: Transcript.Turn) {
        write("\(turn.role == "user" ? "Human" : "Voice"): \(turn.text)", at: turn.at)
    }

    public func note(_ text: String) { write("(\(text))", at: Date()) }

    private func write(_ text: String, at date: Date) {
        let line = "- \(formatter.string(from: date)) · \(text.replacingOccurrences(of: "\n", with: " "))\n"
        guard let handle = try? FileHandle(forWritingTo: url) else { return }
        handle.seekToEndOfFile()
        handle.write(line.data(using: .utf8)!)
        try? handle.close()
    }
}
