import Foundation

/// Presentation-only cleanup. Stored messages and provider payloads stay intact.
enum ChatDisplayText {
    static func removingContextEnvelopes(_ raw: String) -> String {
        var text = raw
        for pattern in [
            "<latest_context>.*?</latest_context>\\s*",
            "<solo:diagnostics>.*?</solo:diagnostics>\\s*"
        ] {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators]) else { continue }
            text = regex.stringByReplacingMatches(
                in: text, range: NSRange(text.startIndex..., in: text), withTemplate: ""
            )
        }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
