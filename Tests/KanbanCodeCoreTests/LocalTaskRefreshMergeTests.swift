import Testing
@testable import KanbanCodeCore

@Suite("Local task refresh merge")
struct LocalTaskRefreshMergeTests {
    @Test("Local task board view excludes unrelated discovered cards")
    func boardViewShowsOnlyLocalTasks() {
        let state = AppState()
        state.links = [
            "local-1": Link(
                id: "local-1",
                name: "#1: local",
                projectPath: "/p",
                column: .backlog,
                source: .manual
            ),
            "session-1": Link(
                id: "session-1",
                name: "discovered session",
                projectPath: "/other",
                column: .backlog,
                source: .discovered,
                sessionLink: SessionLink(sessionId: "session-1")
            ),
        ]
        state.selectedCardId = "session-1"

        state.rebuildCards()

        #expect(state.cards.count == 2)
        #expect(state.filteredCards.map { $0.id } == ["local-1"])
        #expect(state.cards(in: .backlog).map { $0.id } == ["local-1"])
        #expect(state.selectedCard == nil)
    }
}
