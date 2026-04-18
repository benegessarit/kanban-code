import Testing
import Foundation
@testable import KanbanCodeCore

@Suite("ChannelsWatcher")
struct ChannelsWatcherTests {
    private func tmpRoot() -> String {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("kanban-watcher-\(UUID().uuidString)")
            .path
    }

    /// A small race-safe flag that flips when a specific notification arrives.
    final class NotificationFlag: @unchecked Sendable {
        private let lock = NSLock()
        private var _fired = false
        private var _name: String?
        var observer: NSObjectProtocol?

        var fired: Bool {
            lock.lock(); defer { lock.unlock() }
            return _fired
        }
        var firedChannelName: String? {
            lock.lock(); defer { lock.unlock() }
            return _name
        }
        func mark(_ name: String? = nil) {
            lock.lock()
            _fired = true
            _name = name
            lock.unlock()
        }
    }

    private func waitFor(_ flag: NotificationFlag, seconds: Double) async {
        let deadline = Date().addingTimeInterval(seconds)
        while Date() < deadline {
            if flag.fired { return }
            try? await Task.sleep(for: .milliseconds(50))
        }
    }

    @Test func channelsFileChangePostsNotification() async throws {
        let base = tmpRoot()
        defer { try? FileManager.default.removeItem(atPath: base) }
        let channelsDir = (base as NSString).appendingPathComponent("channels")
        try FileManager.default.createDirectory(atPath: channelsDir, withIntermediateDirectories: true)
        let path = (channelsDir as NSString).appendingPathComponent("channels.json")
        try #"{"channels":[]}"#.write(toFile: path, atomically: true, encoding: .utf8)

        let flag = NotificationFlag()
        flag.observer = NotificationCenter.default.addObserver(
            forName: .kanbanCodeChannelsChanged,
            object: nil,
            queue: nil
        ) { _ in flag.mark() }
        defer { if let o = flag.observer { NotificationCenter.default.removeObserver(o) } }

        let watcher = ChannelsWatcher(baseDir: base)
        watcher.start()
        defer { watcher.stop() }
        try await Task.sleep(for: .milliseconds(150))

        // Trigger a write.
        let fh = try FileHandle(forWritingTo: URL(fileURLWithPath: path))
        try fh.seekToEnd()
        try fh.write(contentsOf: Data("\n".utf8))
        try fh.close()

        await waitFor(flag, seconds: 2)
        #expect(flag.fired, "watcher should have posted .kanbanCodeChannelsChanged within 2s")
    }

    @Test func channelLogAppendPostsNotification() async throws {
        let base = tmpRoot()
        defer { try? FileManager.default.removeItem(atPath: base) }
        let channelsDir = (base as NSString).appendingPathComponent("channels")
        try FileManager.default.createDirectory(atPath: channelsDir, withIntermediateDirectories: true)
        let logPath = (channelsDir as NSString).appendingPathComponent("general.jsonl")
        FileManager.default.createFile(atPath: logPath, contents: nil)

        let flag = NotificationFlag()
        flag.observer = NotificationCenter.default.addObserver(
            forName: .kanbanCodeChannelMessagesChanged,
            object: nil,
            queue: nil
        ) { note in
            if let n = note.userInfo?["channelName"] as? String {
                flag.mark(n)
            }
        }
        defer { if let o = flag.observer { NotificationCenter.default.removeObserver(o) } }

        let watcher = ChannelsWatcher(baseDir: base)
        watcher.start()
        defer { watcher.stop() }
        try await Task.sleep(for: .milliseconds(150))

        let line = #"{"id":"m1","ts":"2026-04-18T00:00:00.000Z","from":{"cardId":null,"handle":"user"},"body":"hi","type":"message"}"# + "\n"
        let fh = try FileHandle(forWritingTo: URL(fileURLWithPath: logPath))
        try fh.seekToEnd()
        try fh.write(contentsOf: Data(line.utf8))
        try fh.close()

        await waitFor(flag, seconds: 2)
        #expect(flag.fired)
        #expect(flag.firedChannelName == "general")
    }
}
