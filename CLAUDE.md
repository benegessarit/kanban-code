# Kanban – Claude Code Guidelines

## Build & Test

```bash
swift build          # build the app
swift test           # run all tests
make run-app         # build + launch the app
```

## Architecture

- **KanbanCore** (`Sources/KanbanCore/`) — pure Swift library, no UI. Domain entities, use cases, adapters.
- **Kanban** (`Sources/Kanban/`) — SwiftUI + AppKit macOS app. Views, toolbar, system tray.
- Deployment target: **macOS 26** (swift-tools-version 6.2). No need for `#available` checks.

## Critical: DispatchSource + @MainActor Crashes

SwiftUI Views are `@MainActor`. In Swift 6, closures formed inside `@MainActor` methods inherit that isolation. If a `DispatchSource` event handler runs on a background GCD queue, the runtime asserts and **crashes** (`EXC_BREAKPOINT` in `_dispatch_assert_queue_fail`).

**Never do this** (crashes at runtime, no compile-time warning):
```swift
// Inside a SwiftUI View (which is @MainActor)
func startWatcher() {
    let source = DispatchSource.makeFileSystemObjectSource(fd: fd, eventMask: .write, queue: .global())
    source.setEventHandler {
        // CRASH: this closure inherits @MainActor but runs on a background queue
        NotificationCenter.default.post(name: .myEvent, object: nil)
    }
}
```

**Always do this** — extract to a `nonisolated` context:
```swift
// Option A: nonisolated static factory
private nonisolated static func makeSource(fd: Int32) -> DispatchSourceFileSystemObject {
    let source = DispatchSource.makeFileSystemObjectSource(fd: fd, eventMask: .write, queue: .global())
    source.setEventHandler {
        NotificationCenter.default.post(name: .myEvent, object: nil)
    }
    source.resume()
    return source
}

// Option B: nonisolated async function with AsyncStream
private nonisolated func watchFile(path: String) async {
    let source = DispatchSource.makeFileSystemObjectSource(...)
    let events = AsyncStream<Void> { continuation in
        source.setEventHandler { continuation.yield() }
        source.setCancelHandler { continuation.finish() }
        source.resume()
    }
    for await _ in events {
        NotificationCenter.default.post(name: .myEvent, object: nil)
    }
}
```

This applies to **any** GCD callback (`setEventHandler`, `setCancelHandler`, `DispatchQueue.global().async`) called from a `@MainActor` context.

## Toolbar Layout (macOS 26 Liquid Glass)

Toolbar uses SwiftUI `.toolbar` with `ToolbarSpacer` (macOS 26+) for separate glass pills:

- **`.navigation`** placement = left side. All items merge into ONE pill (spacers don't help).
- **`.principal`** placement = center. Separate pill from navigation.
- **`.primaryAction`** placement = right side. `ToolbarSpacer(.fixed)` DOES create separate pills here.
- Use `Menu` (not `Text`) for items that need their own pill within `.navigation` — menus map to `NSPopUpButton` which gets separate glass automatically.

## Crash Logs

macOS crash reports: `~/Library/Logs/DiagnosticReports/Kanban-*.ips`
App logs: `~/.kanban/logs/kanban.log`
