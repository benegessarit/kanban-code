import SwiftUI
import KanbanCore

struct CardDetailView: View {
    let card: KanbanCard
    var onResume: () -> Void = {}
    var onRename: (String) -> Void = { _ in }
    var onFork: () -> Void = {}
    var onDismiss: () -> Void = {}

    @State private var turns: [ConversationTurn] = []
    @State private var isLoadingHistory = false
    @State private var selectedTab: Int
    @State private var showRenameSheet = false
    @State private var renameText = ""

    // Checkpoint mode
    @State private var checkpointMode = false
    @State private var checkpointTurn: ConversationTurn?
    @State private var showCheckpointConfirm = false

    // Fork
    @State private var showForkConfirm = false
    @State private var forkResult: String?

    // File watcher for real-time history
    @State private var historyWatcherFD: Int32 = -1
    @State private var historyWatcherSource: DispatchSourceFileSystemObject?
    @State private var lastReloadTime: Date = .distantPast

    private let sessionStore = ClaudeCodeSessionStore()

    init(card: KanbanCard, onResume: @escaping () -> Void = {}, onRename: @escaping (String) -> Void = { _ in }, onFork: @escaping () -> Void = {}, onDismiss: @escaping () -> Void = {}) {
        self.card = card
        self.onResume = onResume
        self.onRename = onRename
        self.onFork = onFork
        self.onDismiss = onDismiss
        _selectedTab = State(initialValue: card.link.tmuxSession == nil ? 1 : 0)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(card.displayTitle)
                        .font(.title3)
                        .fontWeight(.semibold)
                        .lineLimit(2)

                    HStack(spacing: 8) {
                        if let projectName = card.projectName {
                            Label(projectName, systemImage: "folder")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        if let branch = card.link.worktreeBranch {
                            Label(branch, systemImage: "arrow.triangle.branch")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Text(card.relativeTime)
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }

                Spacer()
            }
            .padding(16)

            Divider()

            // Tab bar
            Picker("Tab", selection: $selectedTab) {
                Text("Terminal").tag(0)
                Text("History").tag(1)
                Text("Actions").tag(2)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)

            // Content
            switch selectedTab {
            case 0:
                terminalView
            case 1:
                SessionHistoryView(
                    turns: turns,
                    isLoading: isLoadingHistory,
                    checkpointMode: checkpointMode,
                    onSelectTurn: { turn in
                        checkpointTurn = turn
                        showCheckpointConfirm = true
                    }
                )
            case 2:
                actionsView
            default:
                EmptyView()
            }
        }
        .frame(maxWidth: .infinity)
        .task(id: card.id) {
            turns = []
            isLoadingHistory = false
            checkpointMode = false
            await loadHistory()
        }
        .onChange(of: selectedTab) {
            if selectedTab == 1 {
                startHistoryWatcher()
            } else {
                stopHistoryWatcher()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .kanbanHistoryChanged)) { _ in
            guard selectedTab == 1 else { return }
            // Debounce: only reload if >0.5s since last reload
            let now = Date()
            guard now.timeIntervalSince(lastReloadTime) > 0.5 else { return }
            lastReloadTime = now
            Task { await loadHistory() }
        }
        .onDisappear {
            stopHistoryWatcher()
        }
        .sheet(isPresented: $showRenameSheet) {
            RenameSessionDialog(
                currentName: card.link.name ?? card.displayTitle,
                isPresented: $showRenameSheet,
                onRename: onRename
            )
        }
        .alert("Fork Session?", isPresented: $showForkConfirm) {
            Button("Cancel", role: .cancel) {}
            Button("Fork") { performFork() }
        } message: {
            Text("This creates a duplicate session you can resume independently.")
        }
        .alert("Restore to Turn \(checkpointTurn.map { String($0.index + 1) } ?? "")?", isPresented: $showCheckpointConfirm) {
            Button("Cancel", role: .cancel) {
                checkpointTurn = nil
            }
            Button("Restore", role: .destructive) { performCheckpoint() }
        } message: {
            Text("Everything after this point will be removed. A .bkp backup will be created.")
        }
    }

    @ViewBuilder
    private var terminalView: some View {
        if let tmuxSession = card.link.tmuxSession {
            TerminalRepresentable.tmuxAttach(sessionName: tmuxSession)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            VStack(spacing: 12) {
                Image(systemName: "terminal")
                    .font(.system(size: 32))
                    .foregroundStyle(.tertiary)
                Text("No tmux session attached")
                    .font(.body)
                    .foregroundStyle(.secondary)
                Button(action: onResume) {
                    Label("Launch Terminal", systemImage: "play.fill")
                }
                .buttonStyle(.borderedProminent)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var actionsView: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button(action: onResume) {
                Label("Resume Session", systemImage: "play.fill")
            }
            .buttonStyle(.borderedProminent)

            Button(action: { showRenameSheet = true }) {
                Label("Rename", systemImage: "pencil")
            }
            .buttonStyle(.bordered)

            Button(action: { showForkConfirm = true }) {
                Label("Fork Session", systemImage: "arrow.branch")
            }
            .buttonStyle(.bordered)
            .disabled(card.link.sessionPath == nil)

            Button {
                checkpointMode = true
                selectedTab = 1
            } label: {
                Label("Checkpoint / Restore", systemImage: "clock.arrow.circlepath")
            }
            .buttonStyle(.bordered)
            .disabled(card.link.sessionPath == nil || turns.isEmpty)

            Divider()

            Button(action: copyResumeCommand) {
                Label("Copy Resume Command", systemImage: "doc.on.doc")
            }
            .buttonStyle(.bordered)

            if card.link.sessionPath != nil {
                Button(action: { copyToClipboard("claude --resume \(card.link.sessionId)") }) {
                    Label("Copy Session ID", systemImage: "number")
                }
                .buttonStyle(.bordered)
            }

            if let pr = card.link.githubPR {
                Divider()
                Button(action: {}) {
                    Label("Open PR #\(pr)", systemImage: "arrow.up.right.square")
                }
                .buttonStyle(.bordered)
            }

            Spacer()

            if let forkResult {
                HStack {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    Text("Forked: \(forkResult.prefix(8))...")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if let jsonlPath = card.link.sessionPath {
                Text(jsonlPath)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .textSelection(.enabled)
            }
        }
        .padding(16)
    }

    // MARK: - History loading

    private func loadHistory() async {
        guard let path = card.link.sessionPath ?? card.session?.jsonlPath else { return }
        if turns.isEmpty { isLoadingHistory = true }
        do {
            turns = try await TranscriptReader.readTurns(from: path)
        } catch {
            // Silently fail — empty history is fine
        }
        isLoadingHistory = false
    }

    // MARK: - File watcher

    private func startHistoryWatcher() {
        stopHistoryWatcher()
        guard let path = card.link.sessionPath ?? card.session?.jsonlPath else { return }

        let fd = open(path, O_EVTONLY)
        guard fd >= 0 else { return }
        historyWatcherFD = fd

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .extend],
            queue: .global(qos: .userInitiated)
        )
        source.setEventHandler {
            NotificationCenter.default.post(name: .kanbanHistoryChanged, object: nil)
        }
        source.setCancelHandler {
            close(fd)
        }
        source.resume()
        historyWatcherSource = source
    }

    private func stopHistoryWatcher() {
        historyWatcherSource?.cancel()
        historyWatcherSource = nil
        historyWatcherFD = -1
    }

    // MARK: - Fork

    private func performFork() {
        guard let path = card.link.sessionPath else { return }
        Task {
            do {
                let newId = try await sessionStore.forkSession(sessionPath: path)
                forkResult = newId
                onFork()
            } catch {
                // Could show error toast
            }
        }
    }

    // MARK: - Checkpoint

    private func performCheckpoint() {
        guard let path = card.link.sessionPath,
              let turn = checkpointTurn else { return }
        Task {
            do {
                try await sessionStore.truncateSession(sessionPath: path, afterTurn: turn)
                checkpointMode = false
                checkpointTurn = nil
                await loadHistory()
            } catch {
                // Could show error toast
            }
        }
    }

    private func copyResumeCommand() {
        copyToClipboard("claude --resume \(card.link.sessionId)")
    }

    private func copyToClipboard(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}

/// Native rename dialog sheet.
struct RenameSessionDialog: View {
    let currentName: String
    @Binding var isPresented: Bool
    var onRename: (String) -> Void = { _ in }

    @State private var name = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Rename Session")
                .font(.title3)
                .fontWeight(.semibold)

            TextField("Session name", text: $name)
                .textFieldStyle(.roundedBorder)

            HStack {
                Spacer()
                Button("Cancel") {
                    isPresented = false
                }
                .keyboardShortcut(.cancelAction)

                Button("Rename") {
                    let trimmed = name.trimmingCharacters(in: .whitespaces)
                    if !trimmed.isEmpty {
                        onRename(trimmed)
                    }
                    isPresented = false
                }
                .keyboardShortcut(.defaultAction)
                .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(20)
        .frame(width: 350)
        .onAppear {
            name = currentName
        }
    }
}
