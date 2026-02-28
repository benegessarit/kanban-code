import Foundation

/// Coordinates all background processes: session discovery, tmux polling,
/// hook event processing, activity detection, PR tracking, and link management.
@Observable
public final class BackgroundOrchestrator: @unchecked Sendable {
    public var isRunning = false

    private let discovery: SessionDiscovery
    private let coordinationStore: CoordinationStore
    private let activityDetector: ClaudeCodeActivityDetector
    private let hookEventStore: HookEventStore
    private let tmux: TmuxManagerPort?
    private let prTracker: PRTrackerPort?
    private let notificationDedup: NotificationDeduplicator
    private let notifier: NotifierPort?

    private var pollingTask: Task<Void, Never>?

    public init(
        discovery: SessionDiscovery,
        coordinationStore: CoordinationStore,
        activityDetector: ClaudeCodeActivityDetector = .init(),
        hookEventStore: HookEventStore = .init(),
        tmux: TmuxManagerPort? = nil,
        prTracker: PRTrackerPort? = nil,
        notificationDedup: NotificationDeduplicator = .init(),
        notifier: NotifierPort? = nil
    ) {
        self.discovery = discovery
        self.coordinationStore = coordinationStore
        self.activityDetector = activityDetector
        self.hookEventStore = hookEventStore
        self.tmux = tmux
        self.prTracker = prTracker
        self.notificationDedup = notificationDedup
        self.notifier = notifier
    }

    /// Start the background polling loop.
    public func start() {
        guard !isRunning else { return }
        isRunning = true

        pollingTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.tick()
                try? await Task.sleep(for: .seconds(5))
            }
        }
    }

    /// Stop the background polling loop.
    public func stop() {
        pollingTask?.cancel()
        pollingTask = nil
        isRunning = false
    }

    /// Single tick of the orchestration loop.
    public func tick() async {
        // 1. Process hook events
        await processHookEvents()

        // 2. Resolve pending stops (may trigger notifications)
        let resolvedStops = await activityDetector.resolvePendingStops()
        for sessionId in resolvedStops {
            await handleStopResolved(sessionId: sessionId)
        }

        // 3. Update activity states for all links
        await updateActivityStates()

        // 4. Update card columns
        await updateColumns()
    }

    // MARK: - Private

    private func processHookEvents() async {
        do {
            let events = try await hookEventStore.readNewEvents()
            for event in events {
                await activityDetector.handleHookEvent(event)

                // Update dedup tracker
                switch event.eventName {
                case "Stop":
                    let _ = await notificationDedup.recordStop(sessionId: event.sessionId)
                case "UserPromptSubmit":
                    await notificationDedup.recordPrompt(sessionId: event.sessionId)
                default:
                    break
                }
            }
        } catch {
            // Silently continue — hook events are best-effort
        }
    }

    private func handleStopResolved(sessionId: String) async {
        let shouldNotify = await notificationDedup.shouldNotify(sessionId: sessionId)
        guard shouldNotify, let notifier else { return }

        // Get session info for notification
        let link = try? await coordinationStore.linkForSession(sessionId)
        let sessionNum = await notificationDedup.sessionNumber(for: sessionId)
        let title = link?.name ?? "Session #\(sessionNum)"

        try? await notifier.sendNotification(
            title: "Requires Attention",
            message: "\(title) has stopped and needs your input.",
            imageData: nil
        )
    }

    private func updateActivityStates() async {
        do {
            let links = try await coordinationStore.readLinks()
            let sessionPaths = Dictionary(
                links.compactMap { link -> (String, String)? in
                    guard let path = link.sessionPath else { return nil }
                    return (link.sessionId, path)
                },
                uniquingKeysWith: { a, _ in a }
            )

            // Poll activity for sessions without hook events
            let _  = await activityDetector.pollActivity(sessionPaths: sessionPaths)
        } catch {
            // Continue on error
        }
    }

    private func updateColumns() async {
        do {
            var links = try await coordinationStore.readLinks()
            var changed = false

            // Get PR data if tracker available
            var allPRs: [String: PullRequest] = [:]
            if let prTracker {
                // Group links by project for batch PR fetching
                let projects = Set(links.compactMap(\.projectPath))
                for project in projects {
                    if let prs = try? await prTracker.fetchPRs(repoRoot: project) {
                        allPRs.merge(prs) { a, _ in a }
                    }
                }
            }

            // Get tmux sessions
            let tmuxSessions = (try? await tmux?.listSessions()) ?? []
            let tmuxNames = Set(tmuxSessions.map(\.name))

            for i in links.indices {
                let sessionId = links[i].sessionId
                let activityState = await activityDetector.activityState(for: sessionId)
                let pr = links[i].worktreeBranch.flatMap { allPRs[$0] }
                let hasWorktree = links[i].worktreeBranch != nil
                let hasTmux = links[i].tmuxSession.map { tmuxNames.contains($0) } ?? false

                let oldColumn = links[i].column

                UpdateCardColumn.update(
                    link: &links[i],
                    activityState: activityState,
                    pr: pr,
                    hasWorktree: hasWorktree || hasTmux
                )

                if links[i].column != oldColumn {
                    changed = true
                }
            }

            if changed {
                try await coordinationStore.writeLinks(links)
            }
        } catch {
            // Continue on error
        }
    }
}
