import Foundation

/// Sends notifications via macOS native notification center using osascript.
/// Always available as a fallback when Pushover is not configured.
public final class MacOSNotificationClient: NotifierPort, @unchecked Sendable {

    public init() {}

    public func sendNotification(title: String, message: String, imageData: Data?) async throws {
        let escapedTitle = title.replacingOccurrences(of: "\"", with: "\\\"")
        let escapedMessage = message.replacingOccurrences(of: "\"", with: "\\\"")

        let script = """
        display notification "\(escapedMessage)" with title "\(escapedTitle)" sound name "default"
        """

        let result = try await ShellCommand.run(
            "/usr/bin/osascript",
            arguments: ["-e", script]
        )

        guard result.succeeded else {
            throw NotificationError.macOSNotificationFailed
        }
    }

    public func isConfigured() -> Bool {
        true // Always available on macOS
    }
}
