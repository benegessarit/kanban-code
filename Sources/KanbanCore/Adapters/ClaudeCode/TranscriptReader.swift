import Foundation

/// Reads conversation turns from a .jsonl transcript file.
public enum TranscriptReader {

    /// Read all conversation turns from a .jsonl file.
    public static func readTurns(from filePath: String) async throws -> [ConversationTurn] {
        guard FileManager.default.fileExists(atPath: filePath) else { return [] }

        let url = URL(fileURLWithPath: filePath)
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }

        var turns: [ConversationTurn] = []
        var lineNumber = 0
        var turnIndex = 0

        for try await line in handle.bytes.lines {
            lineNumber += 1
            guard !line.isEmpty, line.contains("\"type\"") else { continue }

            guard let data = line.data(using: .utf8),
                  let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let type = obj["type"] as? String else {
                continue
            }

            guard type == "user" || type == "assistant" else { continue }

            let blocks: [ContentBlock]
            let textPreview: String

            if type == "user" {
                blocks = extractUserBlocks(from: obj)
                let textOnly = blocks.filter { if case .text = $0.kind { true } else { false } }
                    .map(\.text).joined(separator: "\n")
                textPreview = textOnly.isEmpty ? "(empty)" : String(textOnly.prefix(500))
            } else {
                blocks = extractAssistantBlocks(from: obj)
                let textOnly = blocks.filter { if case .text = $0.kind { true } else { false } }
                    .map(\.text).joined(separator: "\n")
                textPreview = textOnly.isEmpty
                    ? (blocks.isEmpty ? "(empty)" : "(tool use)")
                    : String(textOnly.prefix(500))
            }

            let timestamp = obj["timestamp"] as? String

            turns.append(ConversationTurn(
                index: turnIndex,
                lineNumber: lineNumber,
                role: type,
                textPreview: textPreview,
                timestamp: timestamp,
                contentBlocks: blocks
            ))
            turnIndex += 1
        }

        return turns
    }

    // MARK: - User message parsing

    static func extractUserBlocks(from obj: [String: Any]) -> [ContentBlock] {
        // User text can be at top level or inside message.content
        if let text = JsonlParser.extractTextContent(from: obj) {
            return [ContentBlock(kind: .text, text: text)]
        }

        // Check for tool_result blocks in message.content
        guard let message = obj["message"] as? [String: Any],
              let content = message["content"] as? [[String: Any]] else {
            return []
        }

        var blocks: [ContentBlock] = []
        for block in content {
            guard let blockType = block["type"] as? String else { continue }
            switch blockType {
            case "text":
                if let text = block["text"] as? String, !text.isEmpty {
                    blocks.append(ContentBlock(kind: .text, text: text))
                }
            case "tool_result":
                let resultText: String
                if let content = block["content"] as? String {
                    let lines = content.components(separatedBy: "\n")
                    resultText = lines.count > 1
                        ? "Result (\(lines.count) lines)"
                        : String(content.prefix(200))
                } else {
                    resultText = "Result"
                }
                blocks.append(ContentBlock(kind: .toolResult(toolName: nil), text: resultText))
            default:
                break
            }
        }
        return blocks
    }

    // MARK: - Assistant message parsing

    static func extractAssistantBlocks(from obj: [String: Any]) -> [ContentBlock] {
        guard let message = obj["message"] as? [String: Any],
              let content = message["content"] else {
            return []
        }

        // Simple string content
        if let text = content as? String {
            return text.isEmpty ? [] : [ContentBlock(kind: .text, text: text)]
        }

        // Array of content blocks
        guard let blocks = content as? [[String: Any]] else { return [] }

        var result: [ContentBlock] = []
        for block in blocks {
            guard let blockType = block["type"] as? String else { continue }
            switch blockType {
            case "text":
                if let text = block["text"] as? String, !text.isEmpty {
                    result.append(ContentBlock(kind: .text, text: text))
                }
            case "tool_use":
                result.append(parseToolUse(block))
            case "thinking":
                if let thinking = block["thinking"] as? String, !thinking.isEmpty {
                    result.append(ContentBlock(kind: .thinking, text: String(thinking.prefix(500))))
                }
            default:
                break
            }
        }
        return result
    }

    // MARK: - Tool use parsing

    static func parseToolUse(_ block: [String: Any]) -> ContentBlock {
        let name = block["name"] as? String ?? "unknown"
        let input = block["input"] as? [String: Any] ?? [:]

        let (displayText, inputMap) = extractToolInfo(name: name, input: input)

        return ContentBlock(
            kind: .toolUse(name: name, input: inputMap),
            text: displayText
        )
    }

    /// Extract display text and key input fields for each tool type.
    static func extractToolInfo(name: String, input: [String: Any]) -> (String, [String: String]) {
        var inputMap: [String: String] = [:]

        switch name {
        case "Bash":
            let command = input["command"] as? String ?? ""
            let desc = input["description"] as? String
            inputMap["command"] = command
            if let desc { inputMap["description"] = desc }
            let display = desc ?? String(command.prefix(200))
            return ("\(name)(\(display))", inputMap)

        case "Read":
            let path = input["file_path"] as? String ?? ""
            inputMap["file_path"] = path
            return ("\(name)(\(shortenPath(path)))", inputMap)

        case "Write":
            let path = input["file_path"] as? String ?? ""
            inputMap["file_path"] = path
            return ("\(name)(\(shortenPath(path)))", inputMap)

        case "Edit":
            let path = input["file_path"] as? String ?? ""
            inputMap["file_path"] = path
            return ("\(name)(\(shortenPath(path)))", inputMap)

        case "Grep":
            let pattern = input["pattern"] as? String ?? ""
            let path = input["path"] as? String
            inputMap["pattern"] = pattern
            if let path { inputMap["path"] = path }
            let pathPart = path.map { " in \(shortenPath($0))" } ?? ""
            return ("\(name)(\"\(pattern)\"\(pathPart))", inputMap)

        case "Glob":
            let pattern = input["pattern"] as? String ?? ""
            inputMap["pattern"] = pattern
            return ("\(name)(\(pattern))", inputMap)

        case "Agent":
            let prompt = input["prompt"] as? String ?? ""
            let desc = input["description"] as? String ?? String(prompt.prefix(80))
            inputMap["prompt"] = String(prompt.prefix(200))
            return ("\(name)(\(desc))", inputMap)

        case "Skill":
            let skill = input["skill"] as? String ?? ""
            inputMap["skill"] = skill
            return ("\(name)(\(skill))", inputMap)

        case "TaskCreate":
            let subject = input["subject"] as? String ?? ""
            inputMap["subject"] = subject
            return ("\(name)(\(subject))", inputMap)

        case "TaskUpdate":
            let taskId = input["taskId"] as? String ?? ""
            let status = input["status"] as? String
            inputMap["taskId"] = taskId
            if let status { inputMap["status"] = status }
            let detail = status.map { "\(taskId): \($0)" } ?? taskId
            return ("\(name)(\(detail))", inputMap)

        default:
            return (name, inputMap)
        }
    }

    /// Shorten a file path for display — keep last 2-3 components.
    static func shortenPath(_ path: String) -> String {
        let components = path.components(separatedBy: "/").filter { !$0.isEmpty }
        if components.count <= 3 { return path }
        return ".../" + components.suffix(3).joined(separator: "/")
    }
}
