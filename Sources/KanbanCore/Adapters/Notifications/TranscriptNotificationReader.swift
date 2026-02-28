import Foundation

/// Extracts the last assistant response from a transcript for notification content.
public enum TranscriptNotificationReader {

    /// Get the last assistant text from a transcript file.
    /// Returns nil if the file doesn't exist or has no assistant turns.
    public static func lastAssistantText(transcriptPath: String) async -> String? {
        guard let turns = try? await TranscriptReader.readTurns(from: transcriptPath) else {
            return nil
        }

        // Find the last assistant turn with text content
        let assistantTurns = turns.filter { $0.role == "assistant" }
        guard let lastTurn = assistantTurns.last else { return nil }

        // Join text-only content blocks
        let textBlocks = lastTurn.contentBlocks.compactMap { block -> String? in
            if case .text = block.kind { return block.text }
            return nil
        }

        let text = textBlocks.joined(separator: "\n")
        return text.isEmpty ? nil : text
    }
}
