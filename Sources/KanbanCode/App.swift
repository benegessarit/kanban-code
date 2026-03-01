import SwiftUI
import AppKit
import UserNotifications
import KanbanCodeCore

@main
struct KanbanCodeApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        WindowGroup {
            ContentView()
                .frame(minWidth: 900, minHeight: 500)
        }
        .defaultSize(width: 1200, height: 700)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New Task") {
                    NotificationCenter.default.post(name: .kanbanCodeNewTask, object: nil)
                }
                .keyboardShortcut("n", modifiers: .command)
            }

            CommandGroup(after: .toolbar) {
                Button("Search Sessions") {
                    NotificationCenter.default.post(name: .kanbanCodeToggleSearch, object: nil)
                }
                .keyboardShortcut("k", modifiers: .command)
            }
        }

        Settings {
            SettingsView()
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate, @unchecked Sendable {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        if let window = NSApp.windows.first {
            window.makeKeyAndOrderFront(nil)
        }

        // Set app icon from bundled resource (SPM uses Bundle.appResources)
        if let iconURL = Bundle.appResources.url(forResource: "AppIcon", withExtension: "icns", subdirectory: "Resources"),
           let icon = NSImage(contentsOf: iconURL) {
            NSApp.applicationIconImage = icon
        }

        // Set up notifications: delegate must be set BEFORE requesting authorization
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        center.requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
            if let error {
                print("[Kanban Code] Notification permission error: \(error)")
            } else if !granted {
                print("[Kanban Code] Notification permission denied")
            }
        }
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        // Check if we have managed tmux sessions running
        let killOnQuit = UserDefaults.standard.bool(forKey: "killTmuxOnQuit")
        let task = Task {
            let tmux = TmuxAdapter()
            let sessions = (try? await tmux.listSessions()) ?? []
            let owned = sessions.filter { $0.name.contains("card_") }
            await MainActor.run {
                if owned.isEmpty {
                    // No managed sessions — quit immediately
                    NSApp.reply(toApplicationShouldTerminate: true)
                } else if killOnQuit {
                    // User already chose to always kill — do it silently
                    Task {
                        for session in owned {
                            try? await tmux.killSession(name: session.name)
                            TerminalCache.shared.remove(session.name)
                        }
                        NSApp.reply(toApplicationShouldTerminate: true)
                    }
                } else {
                    // Show confirmation dialog with sessions already loaded
                    NotificationCenter.default.post(
                        name: .kanbanCodeQuitRequested,
                        object: nil,
                        userInfo: ["sessions": owned]
                    )
                }
            }
        }
        _ = task
        return .terminateLater
    }

    // Show notifications even when the app is in the foreground
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }

    // Handle notification click — open app and select the card
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        if let cardId = response.notification.request.content.userInfo["cardId"] as? String {
            NotificationCenter.default.post(name: .kanbanCodeSelectCard, object: nil, userInfo: ["cardId": cardId])
        }
        MainActor.assumeIsolated {
            NSApp.activate(ignoringOtherApps: true)
        }
        completionHandler()
    }
}


enum AppearanceMode: String, CaseIterable {
    case auto, light, dark

    var next: AppearanceMode {
        switch self {
        case .auto: .dark
        case .dark: .light
        case .light: .auto
        }
    }

    var icon: String {
        switch self {
        case .auto: "circle.lefthalf.filled"
        case .light: "sun.max"
        case .dark: "moon"
        }
    }

    var helpText: String {
        switch self {
        case .auto: "Appearance: Auto (click for Dark)"
        case .dark: "Appearance: Dark (click for Light)"
        case .light: "Appearance: Light (click for Auto)"
        }
    }
}

extension Notification.Name {
    static let kanbanCodeNewTask = Notification.Name("kanbanCodeNewTask")
    static let kanbanCodeToggleSearch = Notification.Name("kanbanCodeToggleSearch")
    static let kanbanCodeHookEvent = Notification.Name("kanbanCodeHookEvent")
    static let kanbanCodeHistoryChanged = Notification.Name("kanbanCodeHistoryChanged")
    static let kanbanCodeSettingsChanged = Notification.Name("kanbanCodeSettingsChanged")
    static let kanbanCodeSelectCard = Notification.Name("kanbanCodeSelectCard")
    static let kanbanCodeQuitRequested = Notification.Name("kanbanCodeQuitRequested")
}
