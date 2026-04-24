import Testing
import Foundation
@testable import KanbanCodeCore

@Suite("CodexActivityDetector")
struct CodexActivityDetectorTests {
    private func writeTempFile(modified: Date) throws -> String {
        let path = "/tmp/kanban-test-codex-activity-\(UUID().uuidString).jsonl"
        try "{}\n".write(toFile: path, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.modificationDate: modified], ofItemAtPath: path)
        return path
    }

    @Test("Polls activity from file modification time")
    func pollsMtime() async throws {
        let active = try writeTempFile(modified: .now.addingTimeInterval(-10))
        let stale = try writeTempFile(modified: .now.addingTimeInterval(-90_000))
        defer {
            try? FileManager.default.removeItem(atPath: active)
            try? FileManager.default.removeItem(atPath: stale)
        }

        let detector = CodexActivityDetector(activeThreshold: 60, attentionThreshold: 120)
        let states = await detector.pollActivity(sessionPaths: [
            "active": active,
            "stale": stale
        ])

        #expect(states["active"] == .activelyWorking)
        #expect(states["stale"] == .stale)
    }

    @Test("Ignores hook events")
    func ignoresHooks() async {
        let detector = CodexActivityDetector()
        await detector.handleHookEvent(HookEvent(sessionId: "s1", eventName: "UserPromptSubmit"))
        let state = await detector.activityState(for: "s1")
        #expect(state == .stale)
    }

    @Test("Ignores non-Codex session paths during poll")
    func filtersOutNonCodexPaths() async throws {
        // Regression: the composite detector used to pick Codex's mtime-based
        // `.activelyWorking` for a just-archived Claude session (transcript was
        // modified seconds earlier), overriding Claude's correct `.ended` and
        // auto-unarchiving the card.
        let claudeDir = "/tmp/kanban-test-cross-\(UUID().uuidString)/.claude/projects"
        try FileManager.default.createDirectory(atPath: claudeDir, withIntermediateDirectories: true)
        let claudePath = "\(claudeDir)/s1.jsonl"
        try "{}\n".write(toFile: claudePath, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(atPath: (claudeDir as NSString).deletingLastPathComponent) }

        let detector = CodexActivityDetector()
        let result = await detector.pollActivity(sessionPaths: ["s1": claudePath])

        #expect(result["s1"] == nil)
    }
}
