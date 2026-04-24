import Testing
import Foundation
@testable import KanbanCodeCore

@Suite("CodexSessionStore")
struct CodexSessionStoreTests {
    private func writeTempSession(_ content: String) throws -> String {
        let path = "/tmp/kanban-test-codex-store-\(UUID().uuidString).jsonl"
        try content.write(toFile: path, atomically: true, encoding: .utf8)
        return path
    }

    private let sampleSession = """
    {"timestamp":"2026-04-19T10:00:00Z","type":"session_meta","payload":{"id":"store-test","cwd":"/tmp/project"}}
    {"timestamp":"2026-04-19T10:00:01Z","type":"response_item","payload":{"type":"message","role":"user","content":[{"type":"input_text","text":"Fix the bug"}]}}
    {"timestamp":"2026-04-19T10:00:02Z","type":"response_item","payload":{"type":"message","role":"assistant","content":[{"type":"output_text","text":"I'll fix it."}]}}
    """

    @Test("Reads transcript")
    func readsTranscript() async throws {
        let path = try writeTempSession(sampleSession)
        defer { try? FileManager.default.removeItem(atPath: path) }

        let turns = try await CodexSessionStore().readTranscript(sessionPath: path)

        #expect(turns.count == 2)
        #expect(turns[0].textPreview == "Fix the bug")
        #expect(turns[1].textPreview == "I'll fix it.")
    }

    @Test("Fork creates rollout-forked file")
    func forkCreatesFile() async throws {
        let path = try writeTempSession(sampleSession)
        defer { try? FileManager.default.removeItem(atPath: path) }

        let store = CodexSessionStore()
        let newId = try await store.forkSession(sessionPath: path)
        let dir = (path as NSString).deletingLastPathComponent
        let forkPath = CodexSessionStore.sessionFilePath(sessionId: newId, in: dir, prefix: "rollout-forked")
        defer { try? FileManager.default.removeItem(atPath: forkPath) }

        #expect(FileManager.default.fileExists(atPath: forkPath))
        let content = try String(contentsOfFile: forkPath, encoding: .utf8)
        #expect(content.contains(newId))
        #expect(!content.contains("\"store-test\""))
    }

    @Test("Truncate keeps lines through selected turn")
    func truncateSession() async throws {
        let path = try writeTempSession(sampleSession)
        defer {
            try? FileManager.default.removeItem(atPath: path)
            try? FileManager.default.removeItem(atPath: path + ".bkp")
        }

        let store = CodexSessionStore()
        let turns = try await store.readTranscript(sessionPath: path)
        try await store.truncateSession(sessionPath: path, afterTurn: turns[0])

        let truncated = try await store.readTranscript(sessionPath: path)
        #expect(truncated.count == 1)
        #expect(FileManager.default.fileExists(atPath: path + ".bkp"))
    }

    @Test("Search finds Codex sessions")
    func searchFindsMatches() async throws {
        let path1 = try writeTempSession("""
        {"timestamp":"2026-04-19T10:00:00Z","type":"session_meta","payload":{"id":"search-1","cwd":"/tmp/project"}}
        {"timestamp":"2026-04-19T10:00:01Z","type":"response_item","payload":{"type":"message","role":"user","content":[{"type":"input_text","text":"Fix login validation"}]}}
        """)
        let path2 = try writeTempSession("""
        {"timestamp":"2026-04-19T10:00:00Z","type":"session_meta","payload":{"id":"search-2","cwd":"/tmp/project"}}
        {"timestamp":"2026-04-19T10:00:01Z","type":"response_item","payload":{"type":"message","role":"user","content":[{"type":"input_text","text":"Add dark mode"}]}}
        """)
        defer {
            try? FileManager.default.removeItem(atPath: path1)
            try? FileManager.default.removeItem(atPath: path2)
        }

        let results = try await CodexSessionStore().searchSessions(query: "login validation", paths: [path1, path2])
        #expect(results.first?.sessionPath == path1)
    }

    @Test("Write session creates native Codex JSONL")
    func writeSession() async throws {
        let dir = "/tmp/kanban-test-codex-store-write-\(UUID().uuidString)"
        defer { try? FileManager.default.removeItem(atPath: dir) }

        let store = CodexSessionStore(codexDir: dir)
        let path = try await store.writeSession(
            turns: [
                ConversationTurn(index: 0, lineNumber: 1, role: "user", textPreview: "Hello"),
                ConversationTurn(index: 1, lineNumber: 2, role: "assistant", textPreview: "Hi")
            ],
            sessionId: "written-session",
            projectPath: "/tmp/project"
        )

        #expect(FileManager.default.fileExists(atPath: path))
        let turns = try await store.readTranscript(sessionPath: path)
        #expect(turns.count == 2)
        #expect(FileManager.default.fileExists(atPath: "\(dir)/session_index.jsonl"))

        // Regression: Codex's TUI renders the chat from `event_msg` lines
        // (type=user_message / type=agent_message), not from `response_item`
        // lines — response_items feed model context on resume but are
        // invisible to the user. Without the paired events, a migrated
        // session opens as an empty chat in `codex resume`.
        let raw = try String(contentsOfFile: path, encoding: .utf8)
        let lines = raw.split(separator: "\n", omittingEmptySubsequences: true)
        let userEvents = lines.filter { $0.contains("\"type\":\"user_message\"") }
        let agentEvents = lines.filter { $0.contains("\"type\":\"agent_message\"") }
        #expect(userEvents.count == 1, "expected one user_message event_msg")
        #expect(agentEvents.count == 1, "expected one agent_message event_msg")
        #expect(userEvents[0].contains("Hello"))
        #expect(agentEvents[0].contains("Hi"))
    }
}
