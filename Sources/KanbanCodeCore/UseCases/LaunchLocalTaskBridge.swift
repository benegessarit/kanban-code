import Foundation

/// Result returned by the runner-tmux-bridge.py process for a local task launch (FT-978).
public struct LocalTaskLaunchResult: Sendable, Equatable {
    public let tmuxSession: String
    public let worktreePath: String
    public let runnerTeam: String
    public let runnerAgent: String
    public let statusPath: String
}

public enum LocalTaskBridgeError: Error, Equatable {
    case bridgeExecutableMissing(path: String)
    case bridgeFailed(exitCode: Int32, stderr: String)
    case malformedJson(stdout: String)
}

/// Calls the Python bridge that launches a tmux-backed Claude session and
/// preserves the runner's leaf-vs-coordinator environment contract.
///
/// The Swift app NEVER synthesizes runner env vars itself — the bridge calls
/// `runner.spawn(launcher="none")` which owns FT_TASK_ID, FT_DB_PATH, and
/// RUNNER_ROLE assignment.
public final class LaunchLocalTaskBridge: @unchecked Sendable {
    private let bridgeExecutable: String
    private let runProcess: (URL, [String]) throws -> ProcessRunResult

    public struct ProcessRunResult: Sendable {
        public let stdout: String
        public let stderr: String
        public let exitCode: Int32

        public init(stdout: String, stderr: String, exitCode: Int32) {
            self.stdout = stdout
            self.stderr = stderr
            self.exitCode = exitCode
        }
    }

    /// - Parameters:
    ///   - bridgeExecutable: Absolute path to `runner-tmux-bridge.py`.
    ///   - runProcess: Hook for tests to stub Process invocation.
    public init(
        bridgeExecutable: String,
        runProcess: @escaping (URL, [String]) throws -> ProcessRunResult = LaunchLocalTaskBridge.defaultRunProcess
    ) {
        self.bridgeExecutable = bridgeExecutable
        self.runProcess = runProcess
    }

    public func launchLeaf(
        taskId: Int,
        repoPath: String,
        prompt: String,
        tmuxSessionName: String,
        team: String = "default"
    ) throws -> LocalTaskLaunchResult {
        let args = baseArgs(repoPath: repoPath, prompt: prompt, tmuxSessionName: tmuxSessionName, team: team)
            + ["--task-id", String(taskId)]
        return try invoke(args: args)
    }

    public func launchCoordinator(
        repoPath: String,
        prompt: String,
        tmuxSessionName: String,
        team: String = "default"
    ) throws -> LocalTaskLaunchResult {
        let args = baseArgs(repoPath: repoPath, prompt: prompt, tmuxSessionName: tmuxSessionName, team: team)
            + ["--coordinator"]
        return try invoke(args: args)
    }

    // MARK: - Private

    private func baseArgs(repoPath: String, prompt: String, tmuxSessionName: String, team: String) -> [String] {
        let promptFile = writePromptFile(prompt)
        return [
            "--repo-path", repoPath,
            "--prompt-file", promptFile,
            "--tmux-session", tmuxSessionName,
            "--team", team,
        ]
    }

    private func writePromptFile(_ prompt: String) -> String {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("kanban-code-prompt-\(UUID().uuidString).txt")
        try? prompt.write(to: tmp, atomically: true, encoding: .utf8)
        return tmp.path
    }

    private func invoke(args: [String]) throws -> LocalTaskLaunchResult {
        let url = URL(fileURLWithPath: bridgeExecutable)
        guard FileManager.default.fileExists(atPath: bridgeExecutable) else {
            throw LocalTaskBridgeError.bridgeExecutableMissing(path: bridgeExecutable)
        }
        let result = try runProcess(url, args)
        guard result.exitCode == 0 else {
            throw LocalTaskBridgeError.bridgeFailed(exitCode: result.exitCode, stderr: result.stderr)
        }
        guard let data = result.stdout.data(using: .utf8),
              let raw = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tmuxSession = raw["tmuxSession"] as? String,
              let worktreePath = raw["worktreePath"] as? String,
              let runnerTeam = raw["runnerTeam"] as? String,
              let runnerAgent = raw["runnerAgent"] as? String,
              let statusPath = raw["statusPath"] as? String
        else {
            throw LocalTaskBridgeError.malformedJson(stdout: result.stdout)
        }
        return LocalTaskLaunchResult(
            tmuxSession: tmuxSession,
            worktreePath: worktreePath,
            runnerTeam: runnerTeam,
            runnerAgent: runnerAgent,
            statusPath: statusPath
        )
    }

    public static func defaultRunProcess(_ executable: URL, _ args: [String]) throws -> ProcessRunResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["python3", executable.path] + args
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe
        try process.run()
        process.waitUntilExit()
        let stdout = String(data: stdoutPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let stderr = String(data: stderrPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        return ProcessRunResult(stdout: stdout, stderr: stderr, exitCode: process.terminationStatus)
    }
}
