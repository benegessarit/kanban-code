# Terminal Performance Notes

## The Problem

SwiftTerm's `LocalProcess` used `DispatchQueue.main.sync` to deliver pty data.
This blocked the read thread whenever the main thread was busy with SwiftUI layout.
With 1M context Claude Code sessions streaming heavy output, the UI froze completely.

Claude Code's TUI uses heavy escape sequences (cursor movement, colors, screen
redraws) that make SwiftTerm's parser particularly slow — up to 12ms per KB,
with spikes to 50ms+ on complex sequences. At 15-30KB/s of streaming output,
the main thread was spending 100%+ of its time in the terminal parser.

## The Fix (Forked SwiftTerm)

One word change: `sync` → `async` in `LocalProcess.childProcessRead`.
The pty read thread never blocks. Data queues up and gets processed in batches.

## Batching Strategy

```
dataReceived → append to buffer → schedule processNextChunk (8ms delay)
processNextChunk → feed 4KB chunks with 4ms time budget → yield to runloop
```

When backlog exceeds 50KB, we drop intermediate frames and keep only the
last 16KB (~1 full screen repaint). Cut point is at a newline boundary
to avoid breaking mid-escape-sequence.

## Measured Performance

During heavy Claude Code streaming (1M context, tool calls + output):

| Metric | Original | sync→async | + drops |
|--------|----------|------------|---------|
| avg feed/call | 8-12ms | 8-12ms | 2-3ms |
| max feed/call | 157ms | 157ms | 43ms |
| backlog | 241KB | 241KB | 32KB |
| UI freezes | constant | reduced | rare |
| data dropped | 0% | 0% | ~75% |

The 75% drop rate is intentional — the terminal only needs the final
screen state, not every intermediate scroll position. tmux sends full
screen repaints so the terminal recovers within 1-2 frames.

### Current Tuning (v3)

```
batchDelay   = 16ms   (1 frame — let data accumulate)
chunkSize    = 2KB    (yield frequently — feed() spikes to 50ms)
timeBudget   = 3ms    (leaves 13ms/frame for UI)
dropAt       = 32KB   (start dropping early)
keep         = 8KB    (half a screen repaint — enough to recover)
```

## Key Files

- `LocalPackages/SwiftTerm/Sources/SwiftTerm/LocalProcess.swift` — async dispatch
- `Sources/KanbanCode/TerminalRepresentable.swift` — BatchedTerminalView

## Stats Logging

Enable by checking `~/.kanban-code/logs/terminal-stats.log`.
Logs every 10 seconds with: receive count/bytes, feed count/bytes,
avg/max feed time, yield count, max backlog, drop count/bytes.

## Future Ideas

- Move `Terminal.parse()` to a background thread (requires SwiftTerm refactor)
- Use Metal rendering instead of Core Graphics (SwiftTerm supports it)
- Reduce escape sequence complexity in Claude Code's TUI
