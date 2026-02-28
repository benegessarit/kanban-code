import SwiftUI
import KanbanCore

struct ContentView: View {
    @State private var boardState: BoardState
    @State private var orchestrator: BackgroundOrchestrator
    @State private var showSearch = false
    @State private var showNewTask = false
    @State private var hooksInstalled = true // assume true until checked
    @AppStorage("appearanceMode") private var appearanceMode: AppearanceMode = .auto
    @State private var hookSetupError: String?
    @State private var showAddFromPath = false
    @State private var addFromPathText = ""
    @AppStorage("selectedProject") private var selectedProjectPersisted: String = ""
    private let coordinationStore: CoordinationStore
    private let settingsStore: SettingsStore
    private let systemTray = SystemTray()
    private let hookEventsPath: String

    private var showInspector: Binding<Bool> {
        Binding(
            get: { boardState.selectedCardId != nil },
            set: { if !$0 { boardState.selectedCardId = nil } }
        )
    }

    init() {
        let discovery = ClaudeCodeSessionDiscovery()
        let coordination = CoordinationStore()
        let settings = SettingsStore()
        let activityDetector = ClaudeCodeActivityDetector()
        let state = BoardState(
            discovery: discovery,
            coordinationStore: coordination,
            activityDetector: activityDetector,
            settingsStore: settings
        )

        // Load Pushover config if available
        let notifier: PushoverClient? = Self.loadPushoverConfig()

        let orch = BackgroundOrchestrator(
            discovery: discovery,
            coordinationStore: coordination,
            activityDetector: activityDetector,
            tmux: TmuxAdapter(),
            notifier: notifier
        )

        _boardState = State(initialValue: state)
        _orchestrator = State(initialValue: orch)
        self.coordinationStore = coordination
        self.settingsStore = settings
        self.hookEventsPath = (NSHomeDirectory() as NSString)
            .appendingPathComponent(".kanban/hook-events.jsonl")
    }

    private static func loadPushoverConfig() -> PushoverClient? {
        let configPath = (NSHomeDirectory() as NSString)
            .appendingPathComponent(".config/claude-pushover/config")
        guard let contents = try? String(contentsOfFile: configPath, encoding: .utf8) else {
            return nil
        }

        var token: String?
        var user: String?
        for line in contents.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("#") || trimmed.isEmpty { continue }
            if trimmed.hasPrefix("PUSHOVER_TOKEN=") {
                token = trimmed.replacingOccurrences(of: "PUSHOVER_TOKEN=", with: "")
                    .trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
            } else if trimmed.hasPrefix("PUSHOVER_USER=") {
                user = trimmed.replacingOccurrences(of: "PUSHOVER_USER=", with: "")
                    .trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
            }
        }

        guard let t = token, let u = user, !t.isEmpty, !u.isEmpty else { return nil }
        return PushoverClient(token: t, userKey: u)
    }

    var body: some View {
        NavigationStack {
        BoardView(state: boardState)
            // Hook onboarding banner
            .overlay(alignment: .top) {
                if !hooksInstalled {
                    hookOnboardingBanner
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
            .animation(.easeInOut(duration: 0.25), value: hooksInstalled)
            .ignoresSafeArea(edges: .top)
            .toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
            .navigationTitle("")
            .inspector(isPresented: showInspector) {
                if let card = boardState.cards.first(where: { $0.id == boardState.selectedCardId }) {
                    CardDetailView(
                        card: card,
                        onRename: { name in
                            boardState.renameCard(cardId: card.id, name: name)
                        },
                        onFork: {},
                        onDismiss: { boardState.selectedCardId = nil }
                    )
                    .inspectorColumnWidth(min: 600, ideal: 800, max: 1000)
                }
            }
            .overlay {
                if showSearch {
                    Color.black.opacity(0.3)
                        .ignoresSafeArea()
                        .onTapGesture { showSearch = false }

                    SearchOverlay(
                        isPresented: $showSearch,
                        cards: boardState.cards,
                        onSelectCard: { card in
                            boardState.selectedCardId = card.id
                        }
                    )
                    .padding(40)
                    .transition(.opacity.combined(with: .scale(scale: 0.95)))
                }
            }
            .animation(.easeInOut(duration: 0.15), value: showSearch)
            .sheet(isPresented: $showNewTask) {
                NewTaskDialog(
                    isPresented: $showNewTask,
                    projects: boardState.configuredProjects,
                    defaultProjectPath: boardState.selectedProjectPath
                ) { title, description, projectPath in
                    createManualTask(title: title, description: description, projectPath: projectPath)
                }
            }
            .sheet(isPresented: $showAddFromPath) {
                addFromPathSheet
            }
            .task {
                hooksInstalled = HookManager.isInstalled()
                applyAppearance()
                // Restore persisted project selection
                boardState.selectedProjectPath = selectedProjectPersisted.isEmpty ? nil : selectedProjectPersisted
                systemTray.setup(boardState: boardState)
                await boardState.refresh()
                systemTray.update()
                orchestrator.start()
            }
            .task(id: "hook-watcher") {
                // Watch hook-events.jsonl for changes → instant refresh
                // Pass path explicitly so watchHookEvents can be nonisolated
                await watchHookEvents(path: hookEventsPath)
            }
            .task(id: "refresh-timer") {
                // Fallback periodic refresh for non-hook changes (new sessions, file mtime)
                while !Task.isCancelled {
                    try? await Task.sleep(for: .seconds(15))
                    guard !Task.isCancelled else { break }
                    await boardState.refresh()
                    systemTray.update()
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .kanbanToggleSearch)) { _ in
                showSearch.toggle()
            }
            .onReceive(NotificationCenter.default.publisher(for: .kanbanNewTask)) { _ in
                showNewTask = true
            }
            .onReceive(NotificationCenter.default.publisher(for: .kanbanHookEvent)) { _ in
                Task {
                    await orchestrator.tick()
                    await boardState.refresh()
                    systemTray.update()
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
                Task {
                    await boardState.refresh()
                    systemTray.update()
                }
            }
            .toolbar {
                // Left: actions pill
                ToolbarItemGroup(placement: .navigation) {
                    Button { showNewTask = true } label: {
                        Image(systemName: "square.and.pencil")
                    }
                    .help("New task (⌘N)")

                    Button { Task { await boardState.refresh() } } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .disabled(boardState.isLoading)
                    .help("Refresh sessions")

                    Button {
                        appearanceMode = appearanceMode.next
                        applyAppearance()
                    } label: {
                        Image(systemName: appearanceMode.icon)
                    }
                    .help(appearanceMode.helpText)
                }

                // Left: project selector pill
                ToolbarItem(placement: .navigation) {
                    projectSelectorMenu
                }

                // Right: search pill
                ToolbarItem(placement: .primaryAction) {
                    Button { showSearch.toggle() } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "magnifyingglass")
                            Text("Search")
                            Text("⌘K")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 1)
                                .background(.quaternary, in: RoundedRectangle(cornerRadius: 4))
                        }
                        .padding(.horizontal, 4)
                    }
                    .help("Search sessions (⌘K)")
                }

                // Spacer between search and sidebar pills
                ToolbarSpacer(.fixed, placement: .primaryAction)

                // Right: sidebar pill
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        if boardState.selectedCardId != nil {
                            boardState.selectedCardId = nil
                        }
                    } label: {
                        Image(systemName: "sidebar.right")
                    }
                    .disabled(boardState.selectedCardId == nil)
                    .opacity(boardState.selectedCardId != nil ? 1.0 : 0.3)
                    .help("Toggle session details")
                }
            }
            .background {
                Button("") { showSearch.toggle() }
                    .keyboardShortcut("k", modifiers: .command)
                    .hidden()
                // Project switching shortcuts ⌘1..⌘9
                Button("") { selectProject(at: 0) }
                    .keyboardShortcut("1", modifiers: .command)
                    .hidden()
                Button("") { selectProject(at: 1) }
                    .keyboardShortcut("2", modifiers: .command)
                    .hidden()
                Button("") { selectProject(at: 2) }
                    .keyboardShortcut("3", modifiers: .command)
                    .hidden()
                Button("") { selectProject(at: 3) }
                    .keyboardShortcut("4", modifiers: .command)
                    .hidden()
                Button("") { selectProject(at: 4) }
                    .keyboardShortcut("5", modifiers: .command)
                    .hidden()
                Button("") { selectProject(at: 5) }
                    .keyboardShortcut("6", modifiers: .command)
                    .hidden()
                Button("") { selectProject(at: 6) }
                    .keyboardShortcut("7", modifiers: .command)
                    .hidden()
                Button("") { selectProject(at: 7) }
                    .keyboardShortcut("8", modifiers: .command)
                    .hidden()
                Button("") { selectProject(at: 8) }
                    .keyboardShortcut("9", modifiers: .command)
                    .hidden()
            }
        } // NavigationStack
    }

    private var hookOnboardingBanner: some View {
        HStack(spacing: 12) {
            Image(systemName: "antenna.radiowaves.left.and.right")
                .foregroundStyle(.orange)
                .font(.title3)

            VStack(alignment: .leading, spacing: 2) {
                Text("Set up Claude Code hooks")
                    .font(.callout)
                    .fontWeight(.medium)
                Text("Kanban needs hooks to detect when Claude is actively working, stops, or needs attention.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let error = hookSetupError {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }

            Spacer()

            Button("Set up for me") {
                do {
                    try HookManager.install()
                    hooksInstalled = true
                    hookSetupError = nil
                } catch {
                    hookSetupError = error.localizedDescription
                }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)

            Button(action: { hooksInstalled = true }) {
                Image(systemName: "xmark")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.borderless)
            .help("Dismiss — Kanban will use file polling as fallback")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10))
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }

    /// Watch ~/.kanban/hook-events.jsonl for writes → post notification (handled by onReceive above).
    /// Must be nonisolated so GCD closures don't inherit @MainActor isolation (causes crash).
    private nonisolated func watchHookEvents(path: String) async {

        // Ensure the directory and file exist
        let dir = (path as NSString).deletingLastPathComponent
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        if !FileManager.default.fileExists(atPath: path) {
            FileManager.default.createFile(atPath: path, contents: nil)
        }

        guard let fd = open(path, O_EVTONLY) as Int32?,
              fd >= 0 else { return }

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .extend],
            queue: .global(qos: .userInitiated)
        )

        // AsyncStream bridges GCD callbacks → async/await without actor isolation issues
        let events = AsyncStream<Void> { continuation in
            source.setEventHandler {
                continuation.yield()
            }
            source.setCancelHandler {
                continuation.finish()
            }
            continuation.onTermination = { @Sendable _ in
                source.cancel()
            }
            source.resume()
        }

        // for-await runs on @MainActor, so posting notifications is safe
        for await _ in events {
            NotificationCenter.default.post(name: .kanbanHookEvent, object: nil)
        }

        close(fd)
    }

    // MARK: - Project Selector Menu

    private var projectSelectorMenu: some View {
        Menu {
            Button {
                setSelectedProject(nil)
            } label: {
                HStack {
                    Text("All Projects")
                    Spacer()
                    if boardState.selectedProjectPath == nil {
                        Image(systemName: "checkmark")
                    }
                }
            }

            let visibleProjects = boardState.configuredProjects.filter(\.visible)
            if !visibleProjects.isEmpty {
                Divider()
                ForEach(visibleProjects) { project in
                    Button {
                        setSelectedProject(project.path)
                    } label: {
                        HStack {
                            Text(project.name)
                            Spacer()
                            if boardState.selectedProjectPath == project.path {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            }

            // Discovered projects (from sessions, not yet configured)
            let discovered = boardState.discoveredProjectPaths
            if !discovered.isEmpty {
                Divider()
                Section("Discovered") {
                    ForEach(discovered.prefix(8), id: \.self) { path in
                        Button {
                            addDiscoveredProject(path: path)
                        } label: {
                            Label(
                                (path as NSString).lastPathComponent,
                                systemImage: "folder.badge.plus"
                            )
                        }
                    }
                }
            }

            Divider()

            Button("Add from folder...") {
                addProjectViaFolderPicker()
            }

            Button("Add from path...") {
                addFromPathText = ""
                showAddFromPath = true
            }

            SettingsLink {
                Text("Settings...")
            }
        } label: {
            Text(currentProjectName)
                .font(.headline)
        }
    }

    private var currentProjectName: String {
        guard let path = boardState.selectedProjectPath else { return "All Projects" }
        return boardState.configuredProjects.first(where: { $0.path == path })?.name
            ?? (path as NSString).lastPathComponent
    }

    private func setSelectedProject(_ path: String?) {
        boardState.selectedProjectPath = path
        selectedProjectPersisted = path ?? ""
    }

    /// Select project by index: 0 = All Projects, 1+ = configured projects by order.
    private func selectProject(at index: Int) {
        if index == 0 {
            setSelectedProject(nil)
            return
        }
        let visibleProjects = boardState.configuredProjects.filter(\.visible)
        let projectIndex = index - 1
        guard projectIndex < visibleProjects.count else { return }
        setSelectedProject(visibleProjects[projectIndex].path)
    }

    private func addProjectViaFolderPicker() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.message = "Select a project directory"
        panel.prompt = "Add Project"

        guard panel.runModal() == .OK, let url = panel.url else { return }
        let path = url.path
        let project = Project(path: path)
        Task {
            try? await settingsStore.addProject(project)
            await boardState.refresh()
            setSelectedProject(path)
        }
    }

    private func addDiscoveredProject(path: String) {
        let project = Project(path: path)
        Task {
            try? await settingsStore.addProject(project)
            await boardState.refresh()
            setSelectedProject(path)
        }
    }

    // MARK: - Add from Path Sheet

    private var addFromPathSheet: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Add Project")
                .font(.title3)
                .fontWeight(.semibold)

            TextField("Project path (e.g. ~/Projects/my-repo)", text: $addFromPathText)
                .textFieldStyle(.roundedBorder)

            HStack {
                Spacer()
                Button("Cancel") {
                    showAddFromPath = false
                }
                .keyboardShortcut(.cancelAction)

                Button("Add") {
                    let path = (addFromPathText as NSString).expandingTildeInPath
                    let project = Project(path: path)
                    Task {
                        try? await settingsStore.addProject(project)
                        await boardState.refresh()
                        setSelectedProject(path)
                    }
                    showAddFromPath = false
                }
                .keyboardShortcut(.defaultAction)
                .disabled(addFromPathText.isEmpty)
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(20)
        .frame(width: 420)
    }

    private func applyAppearance() {
        switch appearanceMode {
        case .auto: NSApp.appearance = nil
        case .light: NSApp.appearance = NSAppearance(named: .aqua)
        case .dark: NSApp.appearance = NSAppearance(named: .darkAqua)
        }
    }

    private func createManualTask(title: String, description: String, projectPath: String?) {
        let link = Link(
            sessionId: UUID().uuidString,
            projectPath: projectPath,
            column: .backlog,
            name: title,
            source: .manual
        )
        Task {
            try? await coordinationStore.upsertLink(link)
            await boardState.refresh()
        }
    }
}
