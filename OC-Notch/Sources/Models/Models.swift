import Foundation

// MARK: - Session

/// Represents an OpenCode session.
struct OCSession: Identifiable, Equatable {
    let id: String
    let slug: String
    let projectID: String
    let directory: String
    let title: String
    var status: OCSessionStatus
    var summary: OCSessionSummary?
    let timeCreated: Date
    var timeUpdated: Date

    var parentID: String?
    var workspaceID: String?
}

enum OCSessionStatus: Equatable {
    case idle
    case busy
    case retry(attempt: Int, message: String, next: Date)
}

struct OCSessionSummary: Equatable {
    let additions: Int
    let deletions: Int
    let files: Int
}

// MARK: - Permission Request

/// A pending permission request from an OpenCode agent.
struct OCPermissionRequest: Identifiable, Equatable {
    let id: String
    let sessionID: String
    let permission: String        // e.g. "bash", "file-write"
    let patterns: [String]
    let metadata: [String: String]
    let always: [String]

    // Enriched from session data
    var sessionTitle: String?

    /// Human-readable description of what the agent wants to do
    var displayDescription: String? {
        // Try to extract command from metadata
        if let command = metadata["command"] {
            return command
        }
        if let path = metadata["path"] {
            return "\(permission): \(path)"
        }
        if patterns.isEmpty == false {
            return patterns.joined(separator: ", ")
        }
        return permission
    }
}

/// Reply options for permission requests
enum PermissionReply: String, Sendable {
    case once = "once"
    case always = "always"
    case reject = "reject"
}

// MARK: - Task Completion

/// Information about a completed agent task.
struct TaskCompletionInfo: Equatable, Identifiable {
    var id: String { sessionID }
    let sessionID: String
    var sessionTitle: String
    var summary: String?
    var filesChanged: Int?
    var additions: Int?
    var deletions: Int?
}

// MARK: - Todo

struct OCTodo: Equatable {
    let content: String
    let status: String   // pending, in_progress, completed, cancelled
    let priority: String // high, medium, low
}

// MARK: - SSE Events

/// Typed events received from the OpenCode SSE stream.
enum OCEvent {
    case serverConnected
    case sessionCreated(sessionID: String, info: OCSession)
    case sessionUpdated(sessionID: String, info: OCSession)
    case sessionDeleted(sessionID: String)
    case sessionStatus(sessionID: String, status: OCSessionStatus)
    case sessionIdle(sessionID: String)
    case permissionAsked(OCPermissionRequest)
    case permissionReplied(sessionID: String, requestID: String, reply: String)
    case questionAsked(OCQuestionRequest)
    case questionReplied(sessionID: String, requestID: String)
    case todoUpdated(sessionID: String, todos: [OCTodo])
    case messagePartUpdated(sessionID: String, part: OCMessagePart)
    case unknown(type: String)
}

// MARK: - Question Request

struct OCQuestionRequest: Identifiable, Equatable {
    let id: String
    let sessionID: String
    let questions: [OCQuestionInfo]
}

struct OCQuestionInfo: Equatable {
    let question: String
    let header: String
    let options: [OCQuestionOption]
    let multiple: Bool
    let custom: Bool
}

struct OCQuestionOption: Equatable {
    let label: String
    let description: String
}

// MARK: - Message Part

struct OCMessagePart: Equatable {
    let id: String
    let sessionID: String
    let messageID: String
    let type: String       // "tool", "text", etc.
    let tool: String?
    let state: OCToolState?
}

enum OCToolState: Equatable {
    case pending
    case running(title: String?)
    case completed(title: String?, output: String?)
    case error(message: String?)
}

// MARK: - OpenCode Instance

/// Represents a discovered OpenCode server instance.
struct OCInstance: Identifiable, Equatable {
    let id: String  // pid or URL-based
    let pid: Int32
    let port: Int
    let hostname: String

    var baseURL: URL {
        URL(string: "http://\(hostname):\(port)")!
    }
}
