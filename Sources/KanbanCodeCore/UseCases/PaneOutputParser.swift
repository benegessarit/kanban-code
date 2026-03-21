import Foundation

/// Parses tmux capture-pane output to detect coding assistant state.
public enum PaneOutputParser {

    /// Count image attachments visible in Claude Code's TUI.
    /// Only counts lines containing `[Image` that also have context like "to select" or "to remove",
    /// to avoid false positives from user-typed text.
    public static func countImages(in paneOutput: String) -> Int {
        // Count actual [Image #N] occurrences, not lines — multiple images can appear on one line
        var count = 0
        var searchRange = paneOutput.startIndex..<paneOutput.endIndex
        while let range = paneOutput.range(of: "[Image #", range: searchRange) {
            count += 1
            searchRange = range.upperBound..<paneOutput.endIndex
        }
        return count
    }

    /// Check if the assistant's input prompt is visible (ready for input).
    public static func isReady(_ paneOutput: String, assistant: CodingAssistant) -> Bool {
        paneOutput.contains(assistant.promptCharacter)
    }

    /// Backward-compatible: check if Claude Code's input prompt is visible.
    public static func isClaudeReady(_ paneOutput: String) -> Bool {
        isReady(paneOutput, assistant: .claude)
    }

    /// Check if Claude Code is actively working by looking for the status line
    /// (e.g. "✶ Brewing… (56s · ↓ 539 tokens)") in the bottom of pane output.
    /// tmux capture-pane includes Unicode control/color codes between the ellipsis
    /// and the parenthesis, so we just search for `…` (U+2026) in the tail.
    public static func isWorking(_ paneOutput: String) -> Bool {
        // Check last ~1000 chars — the status line can be 600+ chars from
        // the end due to the ──── border lines and footer in Claude's TUI.
        let tail = paneOutput.suffix(1000)
        return tail.contains("\u{2026}")
    }

    /// Parse numbered options from Claude Code's plan approval prompt.
    /// Looks for lines matching "❯ N. Option text" or "  N. Option text" pattern
    /// in the pane output. Returns the options in order.
    ///
    /// Example pane output:
    /// ```
    /// ❯ 1. Yes, and bypass permissions
    ///   2. Yes, manually approve edits
    ///   3. Type here to tell Claude what to change
    /// ```
    public static func parsePlanOptions(from paneOutput: String) -> [String] {
        var options: [String] = []
        let lines = paneOutput.components(separatedBy: "\n")

        // Scan from the bottom up to find the option block
        var foundOptions = false
        var rawOptions: [(Int, String)] = []

        for line in lines.reversed() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            // Match "N. text" pattern, optionally preceded by ❯ or spaces
            // Strip ANSI escape codes first
            let clean = stripAnsi(trimmed)

            if let match = parseNumberedOption(clean) {
                rawOptions.insert(match, at: 0)
                foundOptions = true
            } else if foundOptions {
                // We were in the options block and hit a non-option line — stop
                break
            }
        }

        // Sort by number and extract text
        options = rawOptions.sorted { $0.0 < $1.0 }.map(\.1)
        return options
    }

    /// Parse a single numbered option line like "❯ 1. Yes, and bypass permissions"
    /// or "  2. Yes, manually approve edits". Returns (number, text) or nil.
    private static func parseNumberedOption(_ line: String) -> (Int, String)? {
        // Remove leading ❯ or › marker
        var s = line
        if s.hasPrefix("❯") || s.hasPrefix("›") {
            s = String(s.dropFirst()).trimmingCharacters(in: .whitespaces)
        }

        // Match "N. text" where N is a digit
        guard let dotIdx = s.firstIndex(of: "."),
              dotIdx > s.startIndex else { return nil }
        let numStr = String(s[s.startIndex..<dotIdx]).trimmingCharacters(in: .whitespaces)
        guard let num = Int(numStr), num > 0, num < 20 else { return nil }
        let text = String(s[s.index(after: dotIdx)...]).trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return nil }
        return (num, text)
    }

    /// Strip ANSI escape sequences from terminal output.
    private static func stripAnsi(_ s: String) -> String {
        s.replacingOccurrences(
            of: "\\x1B\\[[0-9;]*[A-Za-z]|\\x1B\\]\\d+;[^\\x07]*\\x07",
            with: "",
            options: .regularExpression
        )
    }
}
