import Testing
import Foundation
@testable import KanbanCodeCore

@Suite("LaunchLocalTaskBridge")
struct LaunchLocalTaskBridgeTests {

    private func makeBridgePath() -> String {
        // Real bridge script — only needs to exist; Process is stubbed.
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("kanban-bridge-test-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let path = dir.appendingPathComponent("runner-tmux-bridge.py").path
        try? "#!/usr/bin/env python3\nprint('stub')\n".write(toFile: path, atomically: true, encoding: .utf8)
        return path
    }

    @Test("Leaf launch decodes JSON return shape into LocalTaskLaunchResult")
    func leafLaunchDecodesJson() throws {
        let path = makeBridgePath()
        var capturedArgs: [String] = []
        let bridge = LaunchLocalTaskBridge(
            bridgeExecutable: path,
            runProcess: { _, args in
                capturedArgs = args
                let json = """
                {"tmuxSession":"kanban-978","worktreePath":"/tmp/wt","runnerTeam":"kanban","runnerAgent":"kanban-978","statusPath":"/tmp/state/workers/kanban-978.json"}
                """
                return LaunchLocalTaskBridge.ProcessRunResult(stdout: json, stderr: "", exitCode: 0)
            }
        )

        let result = try bridge.launchLeaf(
            taskId: 978,
            repoPath: "/tmp/repo",
            prompt: "do the thing",
            tmuxSessionName: "kanban-978",
            team: "kanban"
        )

        #expect(result.tmuxSession == "kanban-978")
        #expect(result.worktreePath == "/tmp/wt")
        #expect(result.runnerTeam == "kanban")
        #expect(result.runnerAgent == "kanban-978")
        #expect(result.statusPath == "/tmp/state/workers/kanban-978.json")

        #expect(capturedArgs.contains("--task-id"))
        #expect(capturedArgs.contains("978"))
        #expect(capturedArgs.contains("--repo-path"))
        #expect(capturedArgs.contains("/tmp/repo"))
        #expect(capturedArgs.contains("--tmux-session"))
        #expect(capturedArgs.contains("kanban-978"))
        #expect(capturedArgs.contains("--team"))
        #expect(capturedArgs.contains("kanban"))
        #expect(capturedArgs.contains("--prompt-file"))
    }

    @Test("Coordinator launch passes --coordinator flag and no --task-id")
    func coordinatorLaunchUsesCoordinatorFlag() throws {
        let path = makeBridgePath()
        var capturedArgs: [String] = []
        let bridge = LaunchLocalTaskBridge(
            bridgeExecutable: path,
            runProcess: { _, args in
                capturedArgs = args
                let json = """
                {"tmuxSession":"lead-x","worktreePath":"/tmp/wt","runnerTeam":"kanban","runnerAgent":"lead-x","statusPath":"/tmp/state/workers/lead-x.json"}
                """
                return LaunchLocalTaskBridge.ProcessRunResult(stdout: json, stderr: "", exitCode: 0)
            }
        )

        _ = try bridge.launchCoordinator(
            repoPath: "/tmp/repo",
            prompt: "x",
            tmuxSessionName: "lead-x",
            team: "kanban"
        )

        #expect(capturedArgs.contains("--coordinator"))
        #expect(!capturedArgs.contains("--task-id"))
    }

    @Test("Bridge failure surfaces exit code and stderr")
    func bridgeFailureSurfacesError() {
        let path = makeBridgePath()
        let bridge = LaunchLocalTaskBridge(
            bridgeExecutable: path,
            runProcess: { _, _ in
                LaunchLocalTaskBridge.ProcessRunResult(stdout: "", stderr: #"{"error":"boom"}"#, exitCode: 2)
            }
        )

        do {
            _ = try bridge.launchLeaf(
                taskId: 1,
                repoPath: "/tmp",
                prompt: "x",
                tmuxSessionName: "x",
                team: "kanban"
            )
            Issue.record("expected throw")
        } catch let LocalTaskBridgeError.bridgeFailed(exitCode, stderr) {
            #expect(exitCode == 2)
            #expect(stderr.contains("boom"))
        } catch {
            Issue.record("wrong error: \(error)")
        }
    }

    @Test("Missing bridge executable throws bridgeExecutableMissing")
    func missingBridgeExecutable() {
        let bridge = LaunchLocalTaskBridge(
            bridgeExecutable: "/path/does/not/exist/runner-tmux-bridge.py",
            runProcess: { _, _ in
                LaunchLocalTaskBridge.ProcessRunResult(stdout: "", stderr: "", exitCode: 0)
            }
        )

        do {
            _ = try bridge.launchLeaf(
                taskId: 1,
                repoPath: "/tmp",
                prompt: "x",
                tmuxSessionName: "x",
                team: "kanban"
            )
            Issue.record("expected throw")
        } catch let LocalTaskBridgeError.bridgeExecutableMissing(path) {
            #expect(path.hasSuffix("runner-tmux-bridge.py"))
        } catch {
            Issue.record("wrong error: \(error)")
        }
    }

    @Test("Malformed JSON throws malformedJson")
    func malformedJsonThrows() {
        let path = makeBridgePath()
        let bridge = LaunchLocalTaskBridge(
            bridgeExecutable: path,
            runProcess: { _, _ in
                LaunchLocalTaskBridge.ProcessRunResult(stdout: "not json at all", stderr: "", exitCode: 0)
            }
        )

        do {
            _ = try bridge.launchLeaf(
                taskId: 1,
                repoPath: "/tmp",
                prompt: "x",
                tmuxSessionName: "x",
                team: "kanban"
            )
            Issue.record("expected throw")
        } catch let LocalTaskBridgeError.malformedJson(stdout) {
            #expect(stdout == "not json at all")
        } catch {
            Issue.record("wrong error: \(error)")
        }
    }
}
