import Foundation

/// An `ActivityDetector` implementation that routes operations to the correct
/// assistant-specific detector via the registry. Hook events are forwarded to
/// the default detector (hooks are currently Claude-only). Polling and state
/// queries fan out to all registered detectors and merge results.
public final class CompositeActivityDetector: ActivityDetector, @unchecked Sendable {
    private let registry: CodingAssistantRegistry
    private let defaultDetector: ActivityDetector

    public init(registry: CodingAssistantRegistry, defaultDetector: ActivityDetector) {
        self.registry = registry
        self.defaultDetector = defaultDetector
    }

    /// Route hook events to the default detector (hooks are currently Claude-only).
    public func handleHookEvent(_ event: HookEvent) async {
        await defaultDetector.handleHookEvent(event)
    }

    /// Poll all registered detectors and merge results.
    /// For now, routes all session paths to the default detector since we don't yet
    /// know which assistant each path belongs to. This will be refined when assistant
    /// info is threaded through session paths.
    public func pollActivity(sessionPaths: [String: String]) async -> [String: ActivityState] {
        var merged: [String: ActivityState] = [:]

        for assistant in registry.available {
            guard let detector = registry.detector(for: assistant) else { continue }
            let results = await detector.pollActivity(sessionPaths: sessionPaths)
            merged.merge(results) { existing, _ in existing }
        }

        // Fall back to default detector for any paths not covered by registered detectors
        if merged.isEmpty {
            return await defaultDetector.pollActivity(sessionPaths: sessionPaths)
        }

        return merged
    }

    /// Try each registered detector for the session's activity state.
    /// Returns the first non-stale result found, or falls back to the default detector.
    public func activityState(for sessionId: String) async -> ActivityState {
        for assistant in registry.available {
            guard let detector = registry.detector(for: assistant) else { continue }
            let state = await detector.activityState(for: sessionId)
            if state != .stale {
                return state
            }
        }
        return await defaultDetector.activityState(for: sessionId)
    }
}
