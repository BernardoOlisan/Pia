import Foundation

/// The running text of everything said since the last fresh take.
///
/// ⌥Space starts over; ⌥⇧Space adds to it. Takes are joined by a blank line, because what you are
/// stitching together is thoughts into one prompt, not sentences into one paragraph.
public enum DictationBuffer {
    public static let separator = "\n\n"

    /// What goes to the clipboard: everything kept so far, plus this take.
    /// A missing, empty or whitespace-only buffer just gives the take back, so an appending press with
    /// nothing behind it behaves exactly like a fresh one instead of pasting a leading blank line.
    public static func joined(previous: String?, take: String) -> String {
        let kept = (previous ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let now = take.trimmingCharacters(in: .whitespacesAndNewlines)
        if kept.isEmpty { return now }
        if now.isEmpty { return kept }
        return kept + separator + now
    }

    public static func read(_ url: URL) -> String? {
        try? String(contentsOf: url, encoding: .utf8)
    }
}
