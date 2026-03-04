import SwiftUI
import AppKit
import KanbanCodeCore

private let systemTrayLogDir: String = {
    let dir = (NSHomeDirectory() as NSString).appendingPathComponent(".kanban-code/logs")
    try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
    return dir
}()

/// Manages the menu bar status item (system tray).
/// Shows clawd icon when Claude sessions are actively working.
/// Launches a "clawd" helper .app so Amphetamine can detect it.
@MainActor
final class SystemTray: NSObject, @unchecked Sendable {
    private var statusItem: NSStatusItem?
    private var menu: NSMenu?
    private weak var store: BoardStore?
    private var clawdApp: NSRunningApplication?
    /// Fallback for dev mode (bare binary, no .app bundle).
    private var clawdProcess: Process?
    /// Time when In Progress last had sessions (for linger timeout).
    private var lastActiveTime: Date?
    /// Timer for live-updating the countdown while menu is open.
    private var countdownTimer: Timer?
    /// Reference to the countdown menu item for live updates.
    private weak var countdownItem: NSMenuItem?

    private static let clawdBundleID = "com.kanban-code.clawd"

    /// How long to keep tray visible after last active session.
    /// Reads from UserDefaults (synced with @AppStorage("clawdLingerTimeout") in settings).
    private var lingerTimeout: TimeInterval {
        let stored = UserDefaults.standard.double(forKey: "clawdLingerTimeout")
        return stored > 0 ? stored : 60
    }

    func setup(store: BoardStore) {
        self.store = store
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        // Build icon with 1x + 2x representations for crisp rendering at 22x22pt
        // (same approach as cc-amphetamine's Electron nativeImage)
        let icon = NSImage(size: NSSize(width: 22, height: 22))
        var hasReps = false

        if let url = Bundle.appResources.url(forResource: "clawd", withExtension: "png", subdirectory: "Resources"),
           let rep = NSImageRep(contentsOf: url) {
            rep.size = NSSize(width: 22, height: 22)
            icon.addRepresentation(rep)
            hasReps = true
        }
        if let url = Bundle.appResources.url(forResource: "clawd@2x", withExtension: "png", subdirectory: "Resources"),
           let rep = NSImageRep(contentsOf: url) {
            rep.size = NSSize(width: 22, height: 22) // same logical size; 44px used on retina
            icon.addRepresentation(rep)
            hasReps = true
        }

        if hasReps {
            icon.isTemplate = true
            statusItem?.button?.image = icon
        } else {
            statusItem?.button?.image = NSImage(systemSymbolName: "rectangle.3.group", accessibilityDescription: "Kanban")
        }

        updateMenu()
        updateVisibility()
    }

    func update() {
        updateMenu()
        updateVisibility()
    }

    private func updateMenu() {
        let menu = NSMenu()
        menu.delegate = self

        if let store {
            let activeCards = store.state.cards(in: .inProgress)
            let attentionCards = store.state.cards(in: .waiting)

            // Countdown at the top when lingering (no active sessions)
            if activeCards.isEmpty {
                let item = NSMenuItem(title: countdownText(), action: nil, keyEquivalent: "")
                item.isEnabled = false
                menu.addItem(item)
                countdownItem = item
                if !attentionCards.isEmpty {
                    menu.addItem(NSMenuItem.separator())
                }
            }

            if !activeCards.isEmpty {
                menu.addItem(NSMenuItem.sectionHeader(title: "In Progress"))
                for card in activeCards.prefix(5) {
                    let item = NSMenuItem(title: card.displayTitle, action: nil, keyEquivalent: "")
                    if card.isActivelyWorking {
                        item.image = NSImage(systemSymbolName: "gear.circle.fill", accessibilityDescription: nil)
                    } else {
                        item.image = NSImage(systemSymbolName: "play.circle.fill", accessibilityDescription: nil)
                    }
                    menu.addItem(item)
                }
            }

            if !attentionCards.isEmpty {
                menu.addItem(NSMenuItem.sectionHeader(title: "Waiting"))
                for card in attentionCards.prefix(5) {
                    let item = NSMenuItem(title: card.displayTitle, action: nil, keyEquivalent: "")
                    item.image = NSImage(systemSymbolName: "exclamationmark.circle.fill", accessibilityDescription: nil)
                    menu.addItem(item)
                }
            }
        }

        menu.addItem(NSMenuItem.separator())

        let openItem = NSMenuItem(title: "Open Kanban", action: #selector(openMainWindow), keyEquivalent: "o")
        openItem.target = self
        menu.addItem(openItem)

        menu.addItem(NSMenuItem.separator())

        let quitItem = NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quitItem)

        statusItem?.menu = menu
        self.menu = menu
    }

    private func countdownText() -> String {
        guard let lastActive = lastActiveTime else {
            return "No active sessions"
        }
        let elapsed = Date().timeIntervalSince(lastActive)
        let remaining = max(0, Int(lingerTimeout - elapsed))
        let mins = remaining / 60
        let secs = remaining % 60
        let countdown = mins > 0 ? "\(mins)m \(secs)s" : "\(secs)s"
        return "No active sessions, sleeping in \(countdown)"
    }

    @objc func openMainWindow() {
        NSApp.activate(ignoringOtherApps: true)
        NSApp.windows.first?.makeKeyAndOrderFront(nil)
    }

    /// Show tray icon when there are In Progress sessions, or within linger timeout.
    /// Also manages the "clawd" helper app for Amphetamine integration.
    private func updateVisibility() {
        guard let store else { return }
        let hasActive = store.state.cardCount(in: .inProgress) > 0

        if hasActive {
            lastActiveTime = Date()
            statusItem?.isVisible = true
            startClawdIfNeeded()
        } else if let lastActive = lastActiveTime,
                  Date().timeIntervalSince(lastActive) < lingerTimeout {
            // Linger: keep visible for a bit after last active session
            statusItem?.isVisible = true
            // Keep clawd running during linger
        } else {
            statusItem?.isVisible = false
            stopClawd()
        }
    }

    // MARK: - Clawd helper app (for Amphetamine)

    /// Launches the "clawd" helper .app so Amphetamine can detect it as a running app.
    /// Falls back to bare binary for development (no Amphetamine support).
    private func startClawdIfNeeded() {
        // Already running via .app?
        if let app = clawdApp, !app.isTerminated { return }
        // Already running via bare binary?
        if let proc = clawdProcess, proc.isRunning { return }
        // Check if already running from a previous app launch
        if let existing = NSWorkspace.shared.runningApplications.first(where: { $0.bundleIdentifier == Self.clawdBundleID }) {
            clawdApp = existing
            Self.log("clawd already running: pid=\(existing.processIdentifier)")
            return
        }

        // Try .app bundle first (Amphetamine can detect this)
        if let appURL = Self.findClawdApp() {
            let config = NSWorkspace.OpenConfiguration()
            config.activates = false
            config.addsToRecentItems = false
            NSWorkspace.shared.openApplication(at: appURL, configuration: config) { [weak self] app, error in
                Task { @MainActor in
                    if let error {
                        Self.log("clawd.app failed to start: \(error)")
                    } else if let app {
                        self?.clawdApp = app
                        Self.log("clawd started: pid=\(app.processIdentifier)")
                    }
                }
            }
            return
        }

        // Fallback: bare binary (dev mode — no Amphetamine support)
        if let path = Self.findClawdBinary() {
            let proc = Process()
            proc.executableURL = URL(fileURLWithPath: path)
            proc.qualityOfService = .background
            proc.terminationHandler = { process in
                let reason = process.terminationReason == .exit ? "exit" : "uncaughtSignal"
                Self.log("clawd terminated: status=\(process.terminationStatus) reason=\(reason)")
            }
            do {
                try proc.run()
                clawdProcess = proc
                Self.log("clawd started (bare binary): pid=\(proc.processIdentifier)")
            } catch {
                Self.log("clawd failed to start: \(error)")
            }
            return
        }

        Self.log("clawd not found")
    }

    /// Stop the clawd helper when no more active sessions.
    /// Also discovers and kills orphaned clawd processes from previous app instances.
    private func stopClawd() {
        if let app = clawdApp, !app.isTerminated {
            Self.log("stopping clawd: pid=\(app.processIdentifier)")
            app.terminate()
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
                if let app = self?.clawdApp, !app.isTerminated {
                    app.forceTerminate()
                }
            }
        }
        clawdApp = nil

        if let proc = clawdProcess, proc.isRunning {
            Self.log("stopping clawd (bare): pid=\(proc.processIdentifier)")
            proc.terminate()
        }
        clawdProcess = nil

        // Kill any orphaned clawd from a previous app instance (crash, rebuild, etc.)
        for app in NSWorkspace.shared.runningApplications where app.bundleIdentifier == Self.clawdBundleID && !app.isTerminated {
            Self.log("stopping orphaned clawd: pid=\(app.processIdentifier)")
            app.terminate()
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                if !app.isTerminated { app.forceTerminate() }
            }
        }
    }

    // MARK: - Logging

    nonisolated static func log(_ message: String) {
        let timestamp = ISO8601DateFormatter().string(from: Date())
        let line = "[\(timestamp)] \(message)\n"
        let logPath = (systemTrayLogDir as NSString).appendingPathComponent("kanban.log")
        if let handle = FileHandle(forWritingAtPath: logPath) {
            handle.seekToEndOfFile()
            handle.write(line.data(using: .utf8) ?? Data())
            try? handle.close()
        } else {
            FileManager.default.createFile(atPath: logPath, contents: line.data(using: .utf8))
        }
    }

    /// Find the clawd .app bundle.
    private static func findClawdApp() -> URL? {
        var candidates: [String] = []

        // 1. Inside main app bundle: KanbanCode.app/Contents/Helpers/clawd.app
        candidates.append(
            (Bundle.main.bundlePath as NSString).appendingPathComponent("Contents/Helpers/clawd.app")
        )

        // 2. Next to the main app bundle
        candidates.append(
            ((Bundle.main.bundlePath as NSString).deletingLastPathComponent as NSString)
                .appendingPathComponent("clawd.app")
        )

        for candidate in candidates {
            if FileManager.default.fileExists(atPath: candidate) {
                log("clawd.app found at: \(candidate)")
                return URL(fileURLWithPath: candidate)
            }
        }

        return nil
    }

    /// Find the bare clawd binary (fallback for development).
    private static func findClawdBinary() -> String? {
        var candidates: [String] = []

        // 1. Next to the running Kanban binary (swift run, .app bundle)
        let kanbanPath = ProcessInfo.processInfo.arguments[0]
        let dir = (kanbanPath as NSString).deletingLastPathComponent
        candidates.append((dir as NSString).appendingPathComponent("clawd"))

        // 2. Inside .app bundle's MacOS directory
        if let bundlePath = Bundle.main.executablePath {
            let bundleDir = (bundlePath as NSString).deletingLastPathComponent
            candidates.append((bundleDir as NSString).appendingPathComponent("clawd"))
        }

        // 3. ~/.kanban-code/bin/clawd for installed locations
        candidates.append(
            (NSHomeDirectory() as NSString).appendingPathComponent(".kanban-code/bin/clawd")
        )

        for candidate in candidates {
            if FileManager.default.isExecutableFile(atPath: candidate) {
                log("clawd found at: \(candidate)")
                return candidate
            }
        }

        log("clawd binary not found, searched: \(candidates)")
        return nil
    }
}

// MARK: - NSMenuDelegate (live countdown)

extension SystemTray: NSMenuDelegate {
    nonisolated func menuWillOpen(_ menu: NSMenu) {
        MainActor.assumeIsolated {
            countdownTimer?.invalidate()
            guard countdownItem != nil else { return }
            countdownTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.countdownItem?.title = self?.countdownText() ?? ""
                }
            }
        }
    }

    nonisolated func menuDidClose(_ menu: NSMenu) {
        MainActor.assumeIsolated {
            countdownTimer?.invalidate()
            countdownTimer = nil
        }
    }
}
