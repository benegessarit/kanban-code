import Foundation

// PROTOTYPE: hardcoded per plan §Scope. The first slice ships with one fixed
// epic and one fixed project path; settings come after the first dashboard
// works. Grep for these constants during the post-proof generalization pass.
public let prototypeEpic = "kanban-code-ui-fork"
public let prototypeProjectPath = "/Users/davidbeyer/claude-code"
// Use /usr/bin/env so PATH-based ft resolution works (pyenv shims, brew,
// /usr/local). Hardcoding /usr/local/bin/ft fails on systems with pyenv.
public let prototypeFtBinary = "/usr/bin/env"
public let prototypeFtArgPrefix = ["ft"]

/// One formaltask record exposed to BoardStore. Mirrors the subset of fields
/// available from `ft --json task list` plus a project path supplied by the
/// caller. `description` is reserved for a future SQLite-backed read path.
public struct FormaltaskRecord: Sendable, Equatable {
    public let id: String
    public let title: String
    public let description: String?
    public let status: String
    public let projectPath: String
    public let updatedAt: Date?
}

/// Reads tasks from formaltask via the `ft --json task list <epic>` CLI.
/// Returns an empty array on any process failure — refresh loops must not
/// crash the board because formaltask isn't installed or is mid-migration.
public actor FormaltaskReader {
    private let epic: String
    private let projectPath: String
    private let ftBinary: String
    private let ftArgPrefix: [String]

    public init(
        epic: String = prototypeEpic,
        projectPath: String = prototypeProjectPath,
        ftBinary: String = prototypeFtBinary,
        ftArgPrefix: [String] = prototypeFtArgPrefix
    ) {
        self.epic = epic
        self.projectPath = projectPath
        self.ftBinary = ftBinary
        self.ftArgPrefix = ftArgPrefix
    }

    /// Read the prototype epic's tasks. Returns `[]` and logs on any failure.
    public func read() async -> [FormaltaskRecord] {
        do {
            let data = try shellOut()
            return try Self.parseTaskListJSON(data, projectPath: projectPath)
        } catch {
            KanbanCodeLog.info("formaltask", "read failed: \(error)")
            return []
        }
    }

    private func shellOut() throws -> Data {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: ftBinary)
        process.arguments = ftArgPrefix + ["--json", "task", "list", epic]
        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            let err = String(data: stderr.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            throw FormaltaskReaderError.processFailed(status: process.terminationStatus, stderr: err)
        }
        return stdout.fileHandleForReading.readDataToEndOfFile()
    }

    /// Decode a `ft --json task list` payload into sorted records.
    /// Exposed for unit tests so they can hand in recorded fixtures
    /// without spawning a real process.
    public static func parseTaskListJSON(_ data: Data, projectPath: String) throws -> [FormaltaskRecord] {
        let decoder = JSONDecoder()
        let envelope = try decoder.decode(FtEnvelope.self, from: data)
        guard envelope.success, let payload = envelope.data else {
            throw FormaltaskReaderError.cliReportedFailure(envelope.error ?? "unknown")
        }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let fallback = ISO8601DateFormatter()
        fallback.formatOptions = [.withInternetDateTime]
        let records = payload.tasks.map { task in
            FormaltaskRecord(
                id: String(task.id),
                title: task.title,
                description: nil,
                status: task.status,
                projectPath: projectPath,
                updatedAt: task.started_at.flatMap { formatter.date(from: $0) ?? fallback.date(from: $0) }
            )
        }
        return records.sorted { lhs, rhs in
            (Int(lhs.id) ?? 0) < (Int(rhs.id) ?? 0)
        }
    }
}

public enum FormaltaskReaderError: Error, CustomStringConvertible {
    case processFailed(status: Int32, stderr: String)
    case cliReportedFailure(String)

    public var description: String {
        switch self {
        case .processFailed(let status, let stderr):
            return "ft exited \(status): \(stderr)"
        case .cliReportedFailure(let msg):
            return "ft reported failure: \(msg)"
        }
    }
}

private struct FtEnvelope: Decodable {
    let success: Bool
    let data: FtTaskListData?
    let error: String?
}

private struct FtTaskListData: Decodable {
    let tasks: [FtTask]
    let total: Int?
    let epic_name: String?
}

private struct FtTask: Decodable {
    let id: Int
    let title: String
    let status: String
    let started_at: String?
}
