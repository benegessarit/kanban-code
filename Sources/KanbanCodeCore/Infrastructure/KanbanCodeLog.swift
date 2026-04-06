import Foundation

/// Centralized logging for Kanban Code — writes to ~/.kanban-code/logs/kanban-code.log.
/// Thread-safe, fire-and-forget. Use from anywhere in KanbanCodeCore or Kanban.
public enum KanbanCodeLog {

    /// Max log file size before rotation (10 MB).
    private static let maxLogSize: UInt64 = 10 * 1024 * 1024
    /// Keep this many bytes after rotation (5 MB tail).
    private static let keepAfterRotation: Int = 5 * 1024 * 1024

    private static let logDir: String = {
        let dir = (NSHomeDirectory() as NSString).appendingPathComponent(".kanban-code/logs")
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        return dir
    }()

    private static let logPath: String = {
        let path = (logDir as NSString).appendingPathComponent("kanban-code.log")
        rotateIfNeeded(path: path)
        return path
    }()

    private static let queue = DispatchQueue(label: "kanban-code.log", qos: .utility)

    /// On startup, if the log file exceeds maxLogSize, keep only the tail.
    private static func rotateIfNeeded(path: String) {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: path),
              let size = attrs[.size] as? UInt64,
              size > maxLogSize else { return }
        guard let data = FileManager.default.contents(atPath: path) else { return }
        let tail = data.suffix(keepAfterRotation)
        // Find the first newline in the tail to avoid a partial line
        if let newlineIndex = tail.firstIndex(of: UInt8(ascii: "\n")) {
            let clean = tail[tail.index(after: newlineIndex)...]
            try? Data(clean).write(to: URL(fileURLWithPath: path))
        } else {
            try? Data(tail).write(to: URL(fileURLWithPath: path))
        }
    }

    /// Log a message with a subsystem tag.
    /// Example: `KanbanCodeLog.info("reconciler", "Matched session \(id) to card \(cardId)")`
    public nonisolated static func info(_ subsystem: String, _ message: String) {
        write("INFO", subsystem, message)
    }

    /// Log a warning.
    public nonisolated static func warn(_ subsystem: String, _ message: String) {
        write("WARN", subsystem, message)
    }

    /// Log an error.
    public nonisolated static func error(_ subsystem: String, _ message: String) {
        write("ERROR", subsystem, message)
    }

    private nonisolated static func write(_ level: String, _ subsystem: String, _ message: String) {
        let timestamp = ISO8601DateFormatter().string(from: Date())
        let line = "[\(timestamp)] [\(level)] [\(subsystem)] \(message)\n"

        queue.async {
            if let handle = FileHandle(forWritingAtPath: logPath) {
                handle.seekToEndOfFile()
                handle.write(line.data(using: .utf8) ?? Data())
                handle.closeFile()
            } else {
                FileManager.default.createFile(atPath: logPath, contents: line.data(using: .utf8))
            }
        }
    }
}
