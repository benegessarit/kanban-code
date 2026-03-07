import Foundation

/// Detects Gemini CLI session activity using file modification time polling.
///
/// Phase 1 implementation: polling-only (Gemini hooks are deferred).
/// Checks mtime of session JSON files to infer activity state.
public actor GeminiActivityDetector: ActivityDetector {
    /// Cached activity states from the last poll.
    private var polledStates: [String: ActivityState] = [:]

    /// Thresholds (seconds) for activity detection.
    private let activeThreshold: TimeInterval   // < this = activelyWorking
    private let attentionThreshold: TimeInterval // < this = needsAttention

    public init(activeThreshold: TimeInterval = 120, attentionThreshold: TimeInterval = 300) {
        self.activeThreshold = activeThreshold
        self.attentionThreshold = attentionThreshold
    }

    // MARK: - ActivityDetector

    /// No-op for Phase 1 — Gemini hook support is deferred.
    public func handleHookEvent(_ event: HookEvent) async {
        // Gemini CLI hooks not yet implemented
    }

    /// Poll session file mtimes and return activity states.
    /// - Parameter sessionPaths: Map of sessionId -> file path for each session to check.
    /// - Returns: Map of sessionId -> inferred ActivityState.
    public func pollActivity(sessionPaths: [String: String]) async -> [String: ActivityState] {
        let fileManager = FileManager.default
        var states: [String: ActivityState] = [:]

        for (sessionId, path) in sessionPaths {
            guard let attrs = try? fileManager.attributesOfItem(atPath: path),
                  let mtime = attrs[.modificationDate] as? Date else {
                states[sessionId] = .ended
                continue
            }

            let timeSinceModified = Date.now.timeIntervalSince(mtime)

            if timeSinceModified < activeThreshold {
                // Modified within ~2 minutes — likely actively working
                states[sessionId] = .activelyWorking
            } else if timeSinceModified < attentionThreshold {
                // Modified 2-5 minutes ago — may need attention
                states[sessionId] = .needsAttention
            } else if timeSinceModified < 3600 {
                // 5 min to 1 hour — idle
                states[sessionId] = .idleWaiting
            } else if timeSinceModified < 86400 {
                // 1 hour to 1 day — ended
                states[sessionId] = .ended
            } else {
                states[sessionId] = .stale
            }
        }

        // Cache for activityState(for:) lookups
        for (id, state) in states {
            polledStates[id] = state
        }

        return states
    }

    /// Return the cached activity state for a given session.
    public func activityState(for sessionId: String) async -> ActivityState {
        return polledStates[sessionId] ?? .stale
    }
}
