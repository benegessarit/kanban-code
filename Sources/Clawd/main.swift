import AppKit

// Tiny background-only app that shows up as "clawd" in Activity Monitor
// and is visible to Amphetamine as a registered macOS app.
// Kanban Code launches this .app bundle when Claude sessions are active.
// LSUIElement in Info.plist keeps it out of the Dock.
// NSApplication handles SIGTERM/terminate() properly.

let app = NSApplication.shared
app.run()
