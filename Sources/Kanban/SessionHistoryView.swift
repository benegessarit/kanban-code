import SwiftUI
import KanbanCore

struct SessionHistoryView: View {
    let turns: [ConversationTurn]
    let isLoading: Bool
    var checkpointMode: Bool = false
    var onSelectTurn: ((ConversationTurn) -> Void)?

    @State private var hoveredTurnIndex: Int?

    var body: some View {
        if isLoading {
            VStack {
                ProgressView()
                    .controlSize(.small)
                Text("Loading conversation...")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if turns.isEmpty {
            VStack {
                Image(systemName: "text.bubble")
                    .font(.title2)
                    .foregroundStyle(.tertiary)
                Text("No conversation history")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ZStack {
                Color(white: 0.08)
                    .ignoresSafeArea()

                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 0) {
                            if checkpointMode {
                                checkpointBanner
                            }

                            LazyVStack(alignment: .leading, spacing: 2) {
                                ForEach(turns, id: \.index) { turn in
                                    TurnBlockView(
                                        turn: turn,
                                        checkpointMode: checkpointMode,
                                        isHovered: hoveredTurnIndex == turn.index,
                                        isDimmed: checkpointMode && hoveredTurnIndex != nil && turn.index > hoveredTurnIndex!
                                    )
                                    .id(turn.index)
                                    .onHover { isHovering in
                                        if checkpointMode {
                                            hoveredTurnIndex = isHovering ? turn.index : nil
                                        }
                                    }
                                    .onTapGesture {
                                        if checkpointMode {
                                            onSelectTurn?(turn)
                                        }
                                    }
                                }
                                Color.clear.frame(height: 1).id("bottom-anchor")
                            }
                            .padding(.vertical, 8)
                            .padding(.horizontal, 12)
                        }
                    }
                    .onAppear { scrollToBottom(proxy: proxy) }
                    .onChange(of: turns.count) { scrollToBottom(proxy: proxy) }
                }
            }
        }
    }

    private var checkpointBanner: some View {
        HStack(spacing: 8) {
            Image(systemName: "clock.arrow.circlepath")
                .foregroundStyle(.orange)
            Text("Click a turn to restore to. Everything after will be removed.")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.8))
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.orange.opacity(0.15))
    }

    private func scrollToBottom(proxy: ScrollViewProxy) {
        DispatchQueue.main.async {
            withAnimation(.none) {
                proxy.scrollTo("bottom-anchor", anchor: .bottom)
            }
        }
    }
}

// MARK: - Turn rendering

struct TurnBlockView: View {
    let turn: ConversationTurn
    var checkpointMode: Bool = false
    var isHovered: Bool = false
    var isDimmed: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            if turn.role == "user" {
                userTurnView
            } else {
                assistantTurnView
            }
        }
        .opacity(isDimmed ? 0.3 : 1.0)
        .padding(.vertical, 4)
        .padding(.horizontal, 4)
        .background(
            RoundedRectangle(cornerRadius: 4)
                .fill(isHovered && checkpointMode ? Color.orange.opacity(0.1) : .clear)
        )
        .contentShape(Rectangle())
    }

    // MARK: - User turn

    private var userTurnView: some View {
        VStack(alignment: .leading, spacing: 1) {
            // User text blocks
            let textBlocks = turn.contentBlocks.filter { if case .text = $0.kind { true } else { false } }
            let toolResults = turn.contentBlocks.filter { if case .toolResult = $0.kind { true } else { false } }

            if !textBlocks.isEmpty {
                ForEach(textBlocks.indices, id: \.self) { i in
                    HStack(alignment: .top, spacing: 0) {
                        if i == 0 {
                            Text("❯ ")
                                .font(.system(.caption, design: .monospaced))
                                .foregroundStyle(.green)
                                .fontWeight(.bold)
                        } else {
                            Text("  ")
                                .font(.system(.caption, design: .monospaced))
                        }
                        Text(textBlocks[i].text)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.white)
                            .textSelection(.enabled)
                    }
                }
            } else if !toolResults.isEmpty {
                // Tool result-only user message (auto-response to tool calls)
                ForEach(toolResults.indices, id: \.self) { i in
                    toolResultLine(toolResults[i])
                }
            } else {
                HStack(alignment: .top, spacing: 0) {
                    Text("❯ ")
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.green)
                        .fontWeight(.bold)
                    Text(turn.textPreview)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.white)
                        .textSelection(.enabled)
                }
            }

            // Timestamp
            if let ts = turn.timestamp {
                Text(formatTimestamp(ts))
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(Color(white: 0.4))
                    .padding(.leading, 18)
            }
        }
    }

    // MARK: - Assistant turn

    private var assistantTurnView: some View {
        VStack(alignment: .leading, spacing: 1) {
            if turn.contentBlocks.isEmpty {
                // Fallback for old data without content blocks
                HStack(alignment: .top, spacing: 0) {
                    Text("● ")
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.purple)
                    Text(turn.textPreview)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(Color(white: 0.85))
                        .textSelection(.enabled)
                }
            } else {
                ForEach(turn.contentBlocks.indices, id: \.self) { i in
                    let block = turn.contentBlocks[i]
                    switch block.kind {
                    case .text:
                        textBlockView(block.text, isFirst: i == 0 || !isTextBlock(at: i - 1))
                    case .toolUse(let name, _):
                        toolUseLine(name: name, displayText: block.text)
                    case .toolResult:
                        toolResultLine(block)
                    case .thinking:
                        thinkingLine(block.text)
                    }
                }
            }
        }
    }

    private func isTextBlock(at index: Int) -> Bool {
        guard index >= 0, index < turn.contentBlocks.count else { return false }
        if case .text = turn.contentBlocks[index].kind { return true }
        return false
    }

    // MARK: - Text block

    private func textBlockView(_ text: String, isFirst: Bool) -> some View {
        HStack(alignment: .top, spacing: 0) {
            if isFirst {
                Text("● ")
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.purple)
            } else {
                Text("  ")
                    .font(.system(.caption, design: .monospaced))
            }
            Text(text)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(Color(white: 0.85))
                .textSelection(.enabled)
        }
    }

    // MARK: - Tool use line

    private func toolUseLine(name: String, displayText: String) -> some View {
        HStack(alignment: .top, spacing: 0) {
            Text("  ⎿ ")
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(Color(white: 0.4))
            Text(name)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.cyan.opacity(0.7))
            if displayText != name {
                // Strip tool name prefix to show just the args
                let args = displayText.hasPrefix(name) ? String(displayText.dropFirst(name.count)) : "(\(displayText))"
                Text(args)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(Color(white: 0.5))
                    .lineLimit(2)
            }
        }
    }

    // MARK: - Tool result line

    private func toolResultLine(_ block: ContentBlock) -> some View {
        HStack(alignment: .top, spacing: 0) {
            Text("  ⎿ ")
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(Color(white: 0.4))
            Text(block.text)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(Color(white: 0.4))
                .lineLimit(1)
        }
    }

    // MARK: - Thinking line

    private func thinkingLine(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 0) {
            Text("  💭 ")
                .font(.system(.caption, design: .monospaced))
            Text(String(text.prefix(100)) + (text.count > 100 ? "..." : ""))
                .font(.system(.caption2, design: .monospaced))
                .foregroundStyle(Color(white: 0.35))
                .italic()
                .lineLimit(1)
        }
    }

    // MARK: - Timestamp formatting

    private func formatTimestamp(_ ts: String) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        guard let date = formatter.date(from: ts) ?? ISO8601DateFormatter().date(from: ts) else {
            return ts
        }
        let interval = Date().timeIntervalSince(date)
        if interval < 60 { return "just now" }
        if interval < 3600 { return "\(Int(interval / 60))m ago" }
        if interval < 86400 { return "\(Int(interval / 3600))h ago" }
        return "\(Int(interval / 86400))d ago"
    }
}
