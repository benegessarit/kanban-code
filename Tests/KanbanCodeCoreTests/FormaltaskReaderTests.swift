import Testing
import Foundation
@testable import KanbanCodeCore

@Suite("FormaltaskReader")
struct FormaltaskReaderTests {
    @Test("Decode ft --json task list output into FormaltaskRecord")
    func decodeFtJsonTaskList() throws {
        let json = #"""
        {
          "success": true,
          "data": {
            "tasks": [
              {"id": 976, "title": "Add formaltask cards", "status": "in_progress", "started_at": "2026-05-09T05:57:30.564540Z", "completed_at": null, "due_date": null, "github_pr_number": null},
              {"id": 977, "title": "Map local lifecycle into columns", "status": "open", "started_at": null, "completed_at": null, "due_date": null, "github_pr_number": null}
            ],
            "total": 2,
            "epic_name": "kanban-code-ui-fork"
          }
        }
        """#
        let records = try FormaltaskReader.parseTaskListJSON(
            json.data(using: .utf8)!,
            projectPath: "/Users/davidbeyer/claude-code"
        )
        #expect(records.count == 2)
        #expect(records[0].id == "976")
        #expect(records[0].title == "Add formaltask cards")
        #expect(records[0].status == "in_progress")
        #expect(records[0].projectPath == "/Users/davidbeyer/claude-code")
        #expect(records[0].updatedAt != nil)
        #expect(records[0].description == nil)

        #expect(records[1].id == "977")
        #expect(records[1].status == "open")
        #expect(records[1].updatedAt == nil)
    }

    @Test("Records sort ascending by numeric id even if input is reversed")
    func sortByNumericId() throws {
        let json = #"""
        {"success": true, "data": {"tasks": [
          {"id": 100, "title": "b", "status": "open"},
          {"id": 9, "title": "a", "status": "open"},
          {"id": 50, "title": "c", "status": "open"}
        ], "total": 3, "epic_name": "e"}}
        """#
        let records = try FormaltaskReader.parseTaskListJSON(
            json.data(using: .utf8)!,
            projectPath: "/p"
        )
        #expect(records.map(\.id) == ["9", "50", "100"])
    }

    @Test("Empty task list yields no records")
    func emptyTaskList() throws {
        let json = #"""
        {"success": true, "data": {"tasks": [], "total": 0, "epic_name": "e"}}
        """#
        let records = try FormaltaskReader.parseTaskListJSON(
            json.data(using: .utf8)!,
            projectPath: "/p"
        )
        #expect(records.isEmpty)
    }

    @Test("Failure response throws")
    func failureThrows() {
        let json = #"{"success": false, "error": "epic not found"}"#
        #expect(throws: (any Error).self) {
            try FormaltaskReader.parseTaskListJSON(
                json.data(using: .utf8)!,
                projectPath: "/p"
            )
        }
    }
}
