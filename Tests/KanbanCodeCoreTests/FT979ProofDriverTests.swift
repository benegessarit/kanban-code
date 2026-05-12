// FT-979 proof driver. Not a unit test — a parameterized integration harness
// that runs the production read→merge→write path against the live ft DB and
// captures the resulting links.json to disk for human inspection.
//
// Skipped unless FT979_PROOF_BASEPATH and FT979_PROOF_OUTPUT env vars are set,
// so this never runs in normal `swift test` flows.
//
// Usage:
//   FT979_PROOF_BASEPATH=/tmp/ft979-proof-state \
//   FT979_PROOF_OUTPUT=/path/to/snapshot.json \
//   FT979_PROOF_LABEL=state-N \
//   swift test --filter FT979ProofDriver

import Testing
import Foundation
@testable import KanbanCodeCore

@Suite("FT-979 Proof Driver", .enabled(if: proofEnvSet))
struct FT979ProofDriverTests {
    @Test("Run live read→merge→write and snapshot links.json")
    func runProofRefresh() async throws {
        let env = ProcessInfo.processInfo.environment
        let basePath = env["FT979_PROOF_BASEPATH"]!
        let outputPath = env["FT979_PROOF_OUTPUT"]!
        let label = env["FT979_PROOF_LABEL"] ?? "unlabelled"

        try? FileManager.default.createDirectory(atPath: basePath, withIntermediateDirectories: true)

        let reader = FormaltaskReader()
        let store = CoordinationStore(basePath: basePath)
        let records = await reader.read()

        var linksDict: [String: Link] = [:]
        for link in try await store.readLinks() {
            linksDict[link.id] = link
        }
        let changed = mergeLocalTasksIntoLinks(records, into: &linksDict)
        if changed {
            try await store.writeLinks(Array(linksDict.values))
        }

        // Copy the generated links.json to the requested output path.
        let storePath = await store.path
        let data = try Data(contentsOf: URL(fileURLWithPath: storePath))
        try data.write(to: URL(fileURLWithPath: outputPath))

        FileHandle.standardError.write(Data(
            "[\(label)] proof: \(records.count) records, changed=\(changed), basePath=\(basePath)\n".utf8
        ))
    }
}

private var proofEnvSet: Bool {
    let env = ProcessInfo.processInfo.environment
    return env["FT979_PROOF_BASEPATH"] != nil && env["FT979_PROOF_OUTPUT"] != nil
}
