import Testing
import Foundation
@testable import KanbanCodeCore

@Suite("Local task refresh merge")
struct LocalTaskRefreshMergeTests {
    private func record(_ id: String, status: String = "open", projectPath: String = "/p") -> FormaltaskRecord {
        FormaltaskRecord(id: id, title: "task \(id)", description: nil, status: status, projectPath: projectPath, updatedAt: nil)
    }

    @Test("Empty links + 2 records yields 2 new local-task cards")
    func createMissing() {
        let records = [record("1"), record("2")]
        var links: [String: Link] = [:]
        let changed = mergeLocalTasksIntoLinks(records, into: &links)
        #expect(changed)
        #expect(links.count == 2)
        let local1 = links.values.first { $0.localTaskLink?.id == "1" }
        let local2 = links.values.first { $0.localTaskLink?.id == "2" }
        #expect(local1 != nil)
        #expect(local2 != nil)
        #expect(local1?.source == .localTask)
        #expect(local1?.column == .backlog)
        #expect(local1?.name == "#1: task 1")
        #expect(local1?.projectPath == "/p")
    }

    @Test("Re-running refresh with the same records is a no-op")
    func idempotent() {
        let records = [record("1"), record("2")]
        var links: [String: Link] = [:]
        _ = mergeLocalTasksIntoLinks(records, into: &links)
        let snapshot = links
        let changed = mergeLocalTasksIntoLinks(records, into: &links)
        #expect(!changed)
        #expect(links.keys == snapshot.keys)
        #expect(links.count == 2)
    }

    @Test("Updated record updates name/status/title without creating duplicates")
    func updateExisting() {
        var links: [String: Link] = [:]
        _ = mergeLocalTasksIntoLinks([record("1", status: "open")], into: &links)
        #expect(links.count == 1)

        let updated = FormaltaskRecord(
            id: "1",
            title: "renamed",
            description: nil,
            status: "in_progress",
            projectPath: "/p",
            updatedAt: nil
        )
        let changed = mergeLocalTasksIntoLinks([updated], into: &links)
        #expect(changed)
        #expect(links.count == 1)
        let card = links.values.first!
        #expect(card.localTaskLink?.title == "renamed")
        #expect(card.localTaskLink?.status == "in_progress")
        #expect(card.name == "#1: renamed")
    }

    @Test("Manual cards on the same project are preserved")
    func preserveManualCards() {
        var links: [String: Link] = [:]
        let manual = Link(
            id: "manual-card-x",
            name: "my manual card",
            projectPath: "/p",
            column: .inProgress,
            source: .manual
        )
        links[manual.id] = manual

        let records = [record("1")]
        let changed = mergeLocalTasksIntoLinks(records, into: &links)
        #expect(changed)
        #expect(links.count == 2)
        #expect(links["manual-card-x"]?.name == "my manual card")
        #expect(links["manual-card-x"]?.source == .manual)
    }

    @Test("Stale local-task cards are NOT deleted when their record disappears")
    func preserveStaleLocalCards() {
        var links: [String: Link] = [:]
        _ = mergeLocalTasksIntoLinks([record("1"), record("2")], into: &links)
        #expect(links.count == 2)

        // Now task #2 disappears from the formaltask list (e.g. cancelled, moved epic)
        let changed = mergeLocalTasksIntoLinks([record("1")], into: &links)
        // Either nothing changed or something did, but the stale card MUST still exist
        let stillThere = links.values.contains { $0.localTaskLink?.id == "2" }
        #expect(stillThere, "Removed-from-formaltask cards must not be deleted by refresh")
        _ = changed // not asserting changed-bool; only the preservation invariant
    }

    @Test("Same task id in two project paths makes two distinct cards")
    func projectPathSplitsIdentity() {
        var links: [String: Link] = [:]
        let recA = FormaltaskRecord(id: "1", title: "t", description: nil, status: "open", projectPath: "/a", updatedAt: nil)
        let recB = FormaltaskRecord(id: "1", title: "t", description: nil, status: "open", projectPath: "/b", updatedAt: nil)
        _ = mergeLocalTasksIntoLinks([recA, recB], into: &links)
        #expect(links.count == 2)
    }
}
