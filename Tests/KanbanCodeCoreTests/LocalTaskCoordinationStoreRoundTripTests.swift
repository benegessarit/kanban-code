import Testing
import Foundation
@testable import KanbanCodeCore

@Suite("LocalTask CoordinationStore round-trip")
struct LocalTaskCoordinationStoreRoundTripTests {
    private func tempDir() throws -> String {
        let d = NSTemporaryDirectory() + "kc-localtask-\(UUID().uuidString)"
        try FileManager.default.createDirectory(atPath: d, withIntermediateDirectories: true)
        return d
    }

    @Test("Local task card round-trips through CoordinationStore JSON file")
    func localTaskRoundTrip() async throws {
        let dir = try tempDir()
        defer { try? FileManager.default.removeItem(atPath: dir) }
        let store = CoordinationStore(basePath: dir)

        let local = LocalTaskLink(
            id: "976",
            title: "Add formaltask cards",
            description: nil,
            status: "in_progress",
            projectPath: "/Users/davidbeyer/claude-code",
            updatedAt: Date(timeIntervalSince1970: 1_710_000_000)
        )
        let link = Link(
            name: "#976: Add formaltask cards",
            projectPath: "/Users/davidbeyer/claude-code",
            column: .backlog,
            source: .localTask,
            localTaskLink: local
        )
        try await store.writeLinks([link])

        let read = try await store.readLinks()
        #expect(read.count == 1)
        let restored = read[0]
        #expect(restored.localTaskLink == local)
        #expect(restored.source == .localTask)
        #expect(restored.issueLink == nil)
        #expect(restored.cardLabel == .localTask)
    }
}
