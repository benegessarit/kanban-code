import Testing
import Foundation
@testable import KanbanCodeCore

@Suite("UpdateCardColumn — local task lifecycle")
struct UpdateCardColumnLocalTaskTests {
    private func localCard(_ status: String, column: KanbanCodeColumn = .backlog, manualOverride: Bool = false) -> Link {
        var overrides = ManualOverrides()
        overrides.column = manualOverride
        return Link(
            id: "card-\(status)",
            name: "#1: t",
            projectPath: "/p",
            column: column,
            manualOverrides: overrides,
            source: .localTask,
            localTaskLink: LocalTaskLink(id: "1", title: "t", status: status, projectPath: "/p")
        )
    }

    @Test("open status → backlog")
    func openMapsToBacklog() {
        var card = localCard("open", column: .inProgress)
        UpdateCardColumn.update(link: &card, activityState: nil, hasWorktree: false)
        #expect(card.column == .backlog)
    }

    @Test("in_progress status → inProgress")
    func inProgressMapsToInProgress() {
        var card = localCard("in_progress", column: .backlog)
        UpdateCardColumn.update(link: &card, activityState: nil, hasWorktree: false)
        #expect(card.column == .inProgress)
    }

    @Test("blocked_user status → waiting")
    func blockedMapsToWaiting() {
        var card = localCard("blocked_user", column: .inProgress)
        UpdateCardColumn.update(link: &card, activityState: nil, hasWorktree: false)
        #expect(card.column == .waiting)
    }

    @Test("pending_review status → inReview")
    func pendingReviewMapsToInReview() {
        var card = localCard("pending_review", column: .inProgress)
        UpdateCardColumn.update(link: &card, activityState: nil, hasWorktree: false)
        #expect(card.column == .inReview)
    }

    @Test("completed status → done")
    func completedMapsToDone() {
        var card = localCard("completed", column: .inProgress)
        UpdateCardColumn.update(link: &card, activityState: nil, hasWorktree: false)
        #expect(card.column == .done)
    }

    @Test("cancelled status → done (no separate lane)")
    func cancelledMapsToDone() {
        var card = localCard("cancelled", column: .inProgress)
        UpdateCardColumn.update(link: &card, activityState: nil, hasWorktree: false)
        #expect(card.column == .done)
    }

    // MARK: - Override-precedence tests

    @Test("Local task mapping wins over activelyWorking activity state")
    func localTaskWinsOverActivity() {
        var card = localCard("completed", column: .inProgress)
        UpdateCardColumn.update(link: &card, activityState: .activelyWorking, hasWorktree: true)
        #expect(card.column == .done, "completed formaltask must override .activelyWorking session signal")
    }

    @Test("Local task mapping wins over needsAttention activity state")
    func localTaskWinsOverNeedsAttention() {
        var card = localCard("pending_review", column: .inProgress)
        UpdateCardColumn.update(link: &card, activityState: .needsAttention, hasWorktree: true)
        #expect(card.column == .inReview)
    }

    @Test("Manual user-drag override wins over formaltask status")
    func manualDragWinsOverLocalTask() {
        var card = localCard("completed", column: .inProgress, manualOverride: true)
        UpdateCardColumn.update(link: &card, activityState: nil, hasWorktree: false)
        #expect(card.column == .inProgress, "user-drag must always win — local-task mapping defers to manual override")
    }

    // MARK: - Regression tests

    @Test("Card with issueLink and no localTaskLink keeps existing inference")
    func githubCardUnaffected() {
        // No localTaskLink — should route through existing AssignColumn logic.
        var card = Link(
            id: "gh-1",
            name: "#42: bug",
            projectPath: "/p",
            column: .backlog,
            source: .githubIssue,
            issueLink: IssueLink(number: 42)
        )
        UpdateCardColumn.update(link: &card, activityState: .activelyWorking, hasWorktree: false)
        #expect(card.column == .inProgress, "GitHub-only card must still respond to activity state")
    }

    @Test("Card with both issueLink and localTaskLink — local mapping wins")
    func bothLinksLocalWins() {
        // Edge case the lead called out: someone manually attaches PR/issue
        // metadata to a local-task card. Local mapping must still win.
        let local = LocalTaskLink(id: "1", title: "t", status: "completed", projectPath: "/p")
        var card = Link(
            id: "dual-1",
            name: "#1: t",
            projectPath: "/p",
            column: .backlog,
            source: .localTask,
            issueLink: IssueLink(number: 99),
            localTaskLink: local
        )
        UpdateCardColumn.update(link: &card, activityState: .activelyWorking, hasWorktree: true)
        #expect(card.column == .done)
    }

    @Test("Unknown formaltask status falls through to existing inference")
    func unknownStatusFallsThrough() {
        var card = localCard("some_future_state", column: .backlog)
        UpdateCardColumn.update(link: &card, activityState: .activelyWorking, hasWorktree: false)
        // With activelyWorking activity, AssignColumn returns .inProgress.
        #expect(card.column == .inProgress, "unknown status must defer to existing inference, not crash")
    }
}
