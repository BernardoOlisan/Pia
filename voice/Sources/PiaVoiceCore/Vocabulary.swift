import Foundation

/// The words the transcriber should know: one global list, sent with every take as `keywords[]`.
///
/// It lives outside the plugin, in `vocabulary.txt` next to the other dictation files, because it is
/// about one person's machine — their projects, tools and people — not about PIA. One term per line;
/// `#` starts a comment. Edited by hand, read again on every take, so a change applies to the next one.
///
/// Kept short on purpose: a long list, or one full of ordinary words, makes the model write hinted
/// terms that were never said. Only words a transcriber would otherwise misspell belong here.
public enum Vocabulary {
    /// More than this is cut, and logged: past it the list hurts more than it helps.
    public static let limit = 150

    /// Read the file; nil when it doesn't exist, so the built-in keywords apply.
    public static func load(_ url: URL) -> [String]? {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        return parse(text)
    }

    /// One term per line, `#` comments and blank lines skipped, duplicates (ignoring case) dropped.
    /// `<` and `>` are removed: OpenAI rejects the whole request if a single keyword contains one.
    public static func parse(_ text: String) -> [String] {
        var seen = Set<String>()
        var terms: [String] = []
        for line in text.components(separatedBy: .newlines) {
            let body = line.split(separator: "#", maxSplits: 1, omittingEmptySubsequences: false).first.map(String.init) ?? ""
            let term = body
                .replacingOccurrences(of: "<", with: "")
                .replacingOccurrences(of: ">", with: "")
                .split(whereSeparator: \.isWhitespace).joined(separator: " ")
            guard !term.isEmpty, seen.insert(term.lowercased()).inserted else { continue }
            terms.append(term)
        }
        return terms
    }
}
