import Testing
@testable import KanbanCode
import KanbanCodeCore

@Suite("Board View Mode")
struct BoardViewModeTests {
    @Test("View mode raw values stay stable for persistence")
    func rawValues() {
        #expect(BoardViewMode.kanban.rawValue == "kanban")
        #expect(BoardViewMode.list.rawValue == "list")
    }

    @Test("List sections keep column order and skip empty columns")
    func listSectionsPreserveOrder() {
        let backlog = KanbanCodeCard(link: Link(id: "card_backlog", column: .backlog, updatedAt: .now))
        let waiting = KanbanCodeCard(link: Link(id: "card_waiting", column: .waiting, updatedAt: .now))

        let sections = ListBoardSection.make(
            columns: [.backlog, .inProgress, .waiting, .done],
            cardsInColumn: { column in
                switch column {
                case .backlog: [backlog]
                case .waiting: [waiting]
                default: []
                }
            }
        )

        #expect(sections.count == 2)
        #expect(sections[0].column == .backlog)
        #expect(sections[0].cards.map(\.id) == ["card_backlog"])
        #expect(sections[1].column == .waiting)
        #expect(sections[1].cards.map(\.id) == ["card_waiting"])
    }

    @Test("Collapsed list sections round-trip through storage")
    func collapsedSectionsRoundTrip() {
        let encoded = ListSectionCollapseState.encode([.inReview, .waiting])
        let decoded = ListSectionCollapseState.decode(encoded)

        #expect(decoded == [.inReview, .waiting])
    }
}
