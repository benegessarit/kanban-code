import Foundation

/// The coordination record linking a session to its worktree, tmux session, PR, and board position.
/// Stored in ~/.kanban/links.json.
public struct Link: Identifiable, Codable, Sendable {
    public let id: String
    public var sessionId: String? // Real Claude session UUID, nil until discovered
    public var sessionPath: String? // Full path to .jsonl file
    public var worktreePath: String?
    public var worktreeBranch: String?
    public var tmuxSession: String?
    public var githubIssue: Int?
    public var githubPR: Int?
    public var projectPath: String?
    public var column: KanbanColumn
    public var name: String?
    public var createdAt: Date
    public var updatedAt: Date
    public var lastActivity: Date?
    public var manualOverrides: ManualOverrides
    public var manuallyArchived: Bool
    public var source: LinkSource
    public var sessionNumber: Int?
    public var issueBody: String?

    public init(
        id: String = UUID().uuidString,
        sessionId: String? = nil,
        sessionPath: String? = nil,
        worktreePath: String? = nil,
        worktreeBranch: String? = nil,
        tmuxSession: String? = nil,
        githubIssue: Int? = nil,
        githubPR: Int? = nil,
        projectPath: String? = nil,
        column: KanbanColumn = .allSessions,
        name: String? = nil,
        createdAt: Date = .now,
        updatedAt: Date = .now,
        lastActivity: Date? = nil,
        manualOverrides: ManualOverrides = ManualOverrides(),
        manuallyArchived: Bool = false,
        source: LinkSource = .discovered,
        sessionNumber: Int? = nil,
        issueBody: String? = nil
    ) {
        self.id = id
        self.sessionId = sessionId
        self.sessionPath = sessionPath
        self.worktreePath = worktreePath
        self.worktreeBranch = worktreeBranch
        self.tmuxSession = tmuxSession
        self.githubIssue = githubIssue
        self.githubPR = githubPR
        self.projectPath = projectPath
        self.column = column
        self.name = name
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.lastActivity = lastActivity
        self.manualOverrides = manualOverrides
        self.manuallyArchived = manuallyArchived
        self.source = source
        self.sessionNumber = sessionNumber
        self.issueBody = issueBody
    }
}

/// Tracks which fields have been manually set by the user.
public struct ManualOverrides: Codable, Sendable {
    public var worktreePath: Bool
    public var tmuxSession: Bool
    public var name: Bool
    public var column: Bool

    public init(
        worktreePath: Bool = false,
        tmuxSession: Bool = false,
        name: Bool = false,
        column: Bool = false
    ) {
        self.worktreePath = worktreePath
        self.tmuxSession = tmuxSession
        self.name = name
        self.column = column
    }
}

/// How a link was created.
public enum LinkSource: String, Codable, Sendable {
    case discovered // Found via session scanning
    case hook // Created via Claude hook event
    case githubIssue = "github_issue" // Created from a GitHub issue
    case manual // User-created task
}

/// A single content block within a conversation turn.
public struct ContentBlock: Sendable {
    public enum Kind: Sendable, Equatable {
        case text
        case toolUse(name: String, input: [String: String])
        case toolResult(toolName: String?)
        case thinking
    }

    public let kind: Kind
    public let text: String // rendered text for display

    public init(kind: Kind, text: String) {
        self.kind = kind
        self.text = text
    }
}

/// A conversation turn for history display and checkpoint operations.
public struct ConversationTurn: Sendable {
    public let index: Int
    public let lineNumber: Int
    public let role: String // "user" or "assistant"
    public let textPreview: String
    public let timestamp: String?
    public let contentBlocks: [ContentBlock]

    public init(index: Int, lineNumber: Int, role: String, textPreview: String, timestamp: String? = nil, contentBlocks: [ContentBlock] = []) {
        self.index = index
        self.lineNumber = lineNumber
        self.role = role
        self.textPreview = textPreview
        self.timestamp = timestamp
        self.contentBlocks = contentBlocks
    }
}
