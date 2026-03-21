import Testing
import Foundation
@testable import KanbanCodeCore

@Suite("Plan Options Parser")
struct PlanOptionsParserTests {

    @Test("Parses 3-option plan approval prompt")
    func threeOptions() {
        let pane = """
        Claude has written up a plan and is ready to execute. Would you like to proceed?

        ❯ 1. Yes, and bypass permissions
          2. Yes, manually approve edits
          3. Type here to tell Claude what to change

        ctrl-g to edit in Cursor · ~/.claude/plans/fizzy-moseying-cosmos.md
        """
        let options = PaneOutputParser.parsePlanOptions(from: pane)
        #expect(options.count == 3)
        #expect(options[0] == "Yes, and bypass permissions")
        #expect(options[1] == "Yes, manually approve edits")
        #expect(options[2] == "Type here to tell Claude what to change")
    }

    @Test("Parses 2-option plan approval prompt")
    func twoOptions() {
        let pane = """
        Claude has written up a plan and is ready to execute. Would you like to proceed?

        ❯ 1. Yes, and bypass permissions
          2. Yes, manually approve edits

        ctrl-g to edit in Cursor
        """
        let options = PaneOutputParser.parsePlanOptions(from: pane)
        #expect(options.count == 2)
        #expect(options[0] == "Yes, and bypass permissions")
        #expect(options[1] == "Yes, manually approve edits")
    }

    @Test("Parses options with ANSI escape codes")
    func ansiCodes() {
        let pane = """
        \u{1B}[1m❯ 1. Yes, and bypass permissions\u{1B}[0m
          2. Yes, manually approve edits
          3. Type here to tell Claude what to change
        """
        let options = PaneOutputParser.parsePlanOptions(from: pane)
        #expect(options.count == 3)
        #expect(options[0] == "Yes, and bypass permissions")
    }

    @Test("Returns empty for no options")
    func noOptions() {
        let pane = """
        ⏺ Working on the task...

        ✻ Crunching for 2m 30s
        """
        let options = PaneOutputParser.parsePlanOptions(from: pane)
        #expect(options.isEmpty)
    }

    @Test("Returns empty for regular prompt")
    func regularPrompt() {
        let pane = """
        Done. The file has been updated.

        ───────────────────────
        ❯
        ───────────────────────
        """
        let options = PaneOutputParser.parsePlanOptions(from: pane)
        #expect(options.isEmpty)
    }

    @Test("Parses options with different selection marker")
    func differentMarker() {
        // Sometimes the marker might be › instead of ❯
        let pane = """
        › 1. Yes, and bypass permissions
          2. Yes, manually approve edits
        """
        let options = PaneOutputParser.parsePlanOptions(from: pane)
        #expect(options.count == 2)
    }

    @Test("Options at bottom of long pane output")
    func optionsAtBottom() {
        let pane = """
        A lot of text above
        describing the plan
        in great detail.

        Multiple paragraphs
        of plan content.

        ❯ 1. Yes, and bypass permissions
          2. Yes, manually approve edits
          3. Type here to tell Claude what to change

        ctrl-g to edit in Cursor · ~/.claude/plans/test.md
        """
        let options = PaneOutputParser.parsePlanOptions(from: pane)
        #expect(options.count == 3)
    }

    @Test("Handles AskUserQuestion-style options too")
    func askUserQuestion() {
        let pane = """
        Would you like to:

        ❯ 1. Continue with the current approach
          2. Try a different strategy
          3. Cancel and start over
          4. Let me explain what I need
        """
        let options = PaneOutputParser.parsePlanOptions(from: pane)
        #expect(options.count == 4)
        #expect(options[3] == "Let me explain what I need")
    }
}
