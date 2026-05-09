import Testing
import Foundation
@testable import KanbanCodeCore

/// Integration tests that exercise the live `ft` CLI. Skipped automatically
/// when ft is not on PATH or the prototype epic is unreachable. Provides
/// the proof signal for the FT-976 acceptance criteria.
@Suite("FormaltaskReader live integration", .enabled(if: liveFtAvailable))
struct FormaltaskReaderLiveIntegrationTests {
    @Test("Live ft read returns at least one record for the prototype epic")
    func readReturnsRecords() async {
        let reader = FormaltaskReader()
        let records = await reader.read()
        // We expect at least the FT-976 task itself to be present.
        #expect(!records.isEmpty, "expected ≥1 task in epic \(prototypeEpic) — got 0")
        for record in records {
            #expect(!record.id.isEmpty)
            #expect(!record.title.isEmpty)
            #expect(record.projectPath == prototypeProjectPath)
            // ft list does not currently expose description.
            #expect(record.description == nil)
        }
        // Ascending numeric id sort.
        let ids = records.compactMap { Int($0.id) }
        #expect(ids == ids.sorted())
    }
}

private var liveFtAvailable: Bool {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: prototypeFtBinary)
    process.arguments = prototypeFtArgPrefix + ["--json", "task", "list", prototypeEpic]
    process.standardOutput = Pipe()
    process.standardError = Pipe()
    do {
        try process.run()
        process.waitUntilExit()
        return process.terminationStatus == 0
    } catch {
        return false
    }
}
