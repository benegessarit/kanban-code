import Testing
import Foundation
@testable import KanbanCodeCore

@Suite("PaneOutputParser Multi-Assistant")
struct PaneOutputParserMultiAssistantTests {

    // MARK: - isReady with Claude

    @Test("isReady detects Claude prompt character")
    func isReadyClaude() {
        let output = """
        ────────────────────────────────────────────────────────────
        ❯
        ────────────────────────────────────────────────────────────
        """
        #expect(PaneOutputParser.isReady(output, assistant: .claude) == true)
    }

    @Test("isReady does not detect Gemini prompt as Claude ready")
    func claudeNotReadyWithGeminiPrompt() {
        let output = "> "
        #expect(PaneOutputParser.isReady(output, assistant: .claude) == false)
    }

    // MARK: - isReady with Gemini

    @Test("isReady detects Gemini prompt character")
    func isReadyGemini() {
        // Gemini's prompt character is "> " (with trailing space)
        let output = "Gemini CLI v1.0\nConnected to project.\n> "
        #expect(PaneOutputParser.isReady(output, assistant: .gemini) == true)
    }

    @Test("isReady does not detect Claude prompt as Gemini ready")
    func geminiNotReadyWithClaudePrompt() {
        let output = "❯"
        // "❯" does not contain "> " — so Gemini should not be ready
        #expect(PaneOutputParser.isReady(output, assistant: .gemini) == false)
    }

    @Test("Gemini not ready during startup")
    func geminiNotReadyDuringStartup() {
        let output = "Loading Gemini CLI..."
        #expect(PaneOutputParser.isReady(output, assistant: .gemini) == false)
    }

    // MARK: - isClaudeReady backward compat

    @Test("isClaudeReady delegates to isReady with .claude")
    func isClaudeReadyBackwardCompat() {
        let readyOutput = "❯"
        let notReadyOutput = "loading..."
        #expect(PaneOutputParser.isClaudeReady(readyOutput) == true)
        #expect(PaneOutputParser.isClaudeReady(notReadyOutput) == false)
    }

    // MARK: - Edge cases

    @Test("Empty output is not ready for any assistant")
    func emptyOutputNotReady() {
        #expect(PaneOutputParser.isReady("", assistant: .claude) == false)
        #expect(PaneOutputParser.isReady("", assistant: .gemini) == false)
    }

    @Test("Gemini prompt in middle of output is detected")
    func geminiPromptInMiddle() {
        let output = "Previous response...\n> \nwaiting for input"
        #expect(PaneOutputParser.isReady(output, assistant: .gemini) == true)
    }
}
