import Testing
@testable import KanbanCodeCore

@Suite("KanbanCodeCore")
struct KanbanCodeCoreTests {
    @Test("Version is set")
    func versionIsSet() {
        #expect(KanbanCodeCore.version == "0.1.0")
    }
}
