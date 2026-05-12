import Testing
import Foundation
@testable import KanbanCodeCore

@Suite("LocalTaskLink")
struct LocalTaskLinkTests {
    @Test("LocalTaskLink Codable round-trip with all fields")
    func localTaskLinkCodable() throws {
        let link = LocalTaskLink(
            id: "976",
            title: "Add formaltask cards",
            description: "Wire local task metadata into the kanban model.",
            status: "in_progress",
            projectPath: "/Users/davidbeyer/claude-code",
            updatedAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
        let data = try JSONEncoder().encode(link)
        let decoded = try JSONDecoder().decode(LocalTaskLink.self, from: data)
        #expect(decoded == link)
        #expect(decoded.id == "976")
        #expect(decoded.title == "Add formaltask cards")
        #expect(decoded.status == "in_progress")
    }

    @Test("LocalTaskLink decodes without optional description and updatedAt")
    func localTaskLinkOptionalsAbsent() throws {
        let json = #"{"id":"42","title":"task","status":"open","projectPath":"/p"}"#
        let decoded = try JSONDecoder().decode(LocalTaskLink.self, from: json.data(using: .utf8)!)
        #expect(decoded.id == "42")
        #expect(decoded.description == nil)
        #expect(decoded.updatedAt == nil)
    }

    @Test("Link round-trip with localTaskLink populated")
    func linkWithLocalTaskCodable() throws {
        let local = LocalTaskLink(id: "100", title: "test", status: "open", projectPath: "/p")
        let link = Link(
            name: "#100: test",
            projectPath: "/p",
            column: .backlog,
            source: .localTask,
            localTaskLink: local
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let data = try encoder.encode(link)
        let decoded = try decoder.decode(Link.self, from: data)
        #expect(decoded.localTaskLink == local)
        #expect(decoded.source == .localTask)
        #expect(decoded.issueLink == nil)
    }

    @Test("Link backward-compat decodes legacy JSON without localTaskLink")
    func linkBackwardCompatNoLocalTask() throws {
        let json = #"""
        {"id":"card-x","column":"backlog","createdAt":"2026-01-01T00:00:00Z","updatedAt":"2026-01-01T00:00:00Z","manualOverrides":{},"manuallyArchived":false,"source":"manual","isRemote":false,"prLinks":[]}
        """#
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(Link.self, from: json.data(using: .utf8)!)
        #expect(decoded.localTaskLink == nil)
        #expect(decoded.source == .manual)
    }

    @Test("Link cardLabel is .localTask when only localTaskLink is set")
    func cardLabelLocalTask() {
        let local = LocalTaskLink(id: "1", title: "t", status: "open", projectPath: "/p")
        let link = Link(source: .localTask, localTaskLink: local)
        #expect(link.cardLabel == .localTask)
    }

    @Test("Link cardLabel prefers session over localTask when both present")
    func cardLabelSessionWinsOverLocalTask() {
        let local = LocalTaskLink(id: "1", title: "t", status: "open", projectPath: "/p")
        let link = Link(
            source: .localTask,
            sessionLink: SessionLink(sessionId: "s1"),
            localTaskLink: local
        )
        #expect(link.cardLabel == .session)
    }

    @Test("LinkSource.localTask raw value is local_task")
    func linkSourceRawValue() {
        #expect(LinkSource.localTask.rawValue == "local_task")
    }
}
