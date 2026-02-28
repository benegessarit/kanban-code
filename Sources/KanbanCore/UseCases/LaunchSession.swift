import Foundation

/// Launches a new Claude Code session inside a tmux session.
/// Does NOT manage Link records — the caller owns link lifecycle.
public final class LaunchSession: SessionLauncher, @unchecked Sendable {
    private let tmux: TmuxManagerPort

    public init(tmux: TmuxManagerPort) {
        self.tmux = tmux
    }

    public func launch(
        projectPath: String,
        prompt: String,
        worktreeName: String?,
        shellOverride: String?
    ) async throws -> String {
        let sessionName = tmuxSessionName(project: projectPath, worktree: worktreeName)

        // Build the claude command
        var cmd = "claude"
        if let worktreeName {
            cmd += " --worktree \(worktreeName)"
        }
        if let shellOverride {
            cmd = "SHELL=\(shellOverride) \(cmd)"
        }

        cmd += " -p \(shellEscape(prompt))"

        try await tmux.createSession(name: sessionName, path: projectPath, command: cmd)
        return sessionName
    }

    public func resume(
        sessionId: String,
        projectPath: String,
        shellOverride: String?
    ) async throws -> String {
        // Check if there's already a tmux session for this
        let existing = try await tmux.listSessions()
        if let match = existing.first(where: { $0.name.contains(String(sessionId.prefix(8))) }) {
            return match.name
        }

        // Create new tmux session with resume command
        let sessionName = "claude-\(String(sessionId.prefix(8)))"
        var cmd = "claude --resume \(sessionId)"
        if let shellOverride {
            cmd = "SHELL=\(shellOverride) \(cmd)"
        }

        try await tmux.createSession(name: sessionName, path: projectPath, command: cmd)
        return sessionName
    }

    private func tmuxSessionName(project: String, worktree: String?) -> String {
        let projectName = (project as NSString).lastPathComponent
        if let worktree {
            return "\(projectName)-\(worktree)"
        }
        return projectName
    }

    private func shellEscape(_ str: String) -> String {
        "'" + str.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
