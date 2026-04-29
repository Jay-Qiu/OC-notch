import Foundation
import os

private let logger = Logger(subsystem: "com.oc-notch.app", category: "SSEClient")

/// Connects to an OpenCode instance's SSE event stream at `/global/event`.
/// Parses incoming events into typed `OCEvent` values.
actor OpenCodeSSEClient {
    let instance: OCInstance
    private var eventTask: Task<Void, Never>?

    init(instance: OCInstance) {
        self.instance = instance
    }

    /// Connect to the SSE stream and yield parsed events.
    func connect() -> AsyncStream<OCEvent> {
        AsyncStream { continuation in
            let task = Task {
                await self.streamEvents(continuation: continuation)
            }
            self.eventTask = task
            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }

    func disconnect() {
        eventTask?.cancel()
        eventTask = nil
    }

    // MARK: - Private

    private func streamEvents(continuation: AsyncStream<OCEvent>.Continuation) async {
        let url = instance.baseURL.appendingPathComponent("global/event")
        var request = URLRequest(url: url)
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        request.timeoutInterval = .infinity

        do {
            let (bytes, response) = try await URLSession.shared.bytes(for: request)

            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else {
                logger.error("SSE connection failed: bad response")
                continuation.finish()
                return
            }

            logger.notice("SSE connected to \(self.instance.baseURL)")

            var dataBuffer = ""

            for try await line in bytes.lines {
                if Task.isCancelled { break }

                if line.hasPrefix("data: ") {
                    if dataBuffer.isEmpty == false {
                        dataBuffer += "\n"
                    }
                    dataBuffer += String(line.dropFirst(6))
                } else if line.isEmpty && dataBuffer.isEmpty == false {
                    // End of event — parse accumulated data
                    if let event = parseEvent(json: dataBuffer) {
                        continuation.yield(event)
                    }
                    dataBuffer = ""
                }
            }
        } catch {
            if Task.isCancelled == false {
                logger.error("SSE stream error: \(error)")
            }
        }

        continuation.finish()
    }

    // MARK: - Event Parsing

    private func parseEvent(json: String) -> OCEvent? {
        guard let data = json.data(using: .utf8),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }

        // GlobalEvent wraps { directory, payload: { type, properties } }
        let payload: [String: Any]
        if let p = root["payload"] as? [String: Any] {
            payload = p
        } else {
            payload = root
        }

        guard let type = payload["type"] as? String else { return nil }
        let properties = payload["properties"] as? [String: Any] ?? [:]

        switch type {
        case "server.connected":
            return .serverConnected

        case "session.created":
            guard let sessionID = properties["sessionID"] as? String,
                  let info = properties["info"] as? [String: Any] else { return nil }
            return .sessionCreated(sessionID: sessionID, info: parseSession(info))

        case "session.updated":
            guard let sessionID = properties["sessionID"] as? String,
                  let info = properties["info"] as? [String: Any] else { return nil }
            return .sessionUpdated(sessionID: sessionID, info: parseSession(info))

        case "session.deleted":
            guard let sessionID = properties["sessionID"] as? String else { return nil }
            return .sessionDeleted(sessionID: sessionID)

        case "session.status":
            guard let sessionID = properties["sessionID"] as? String,
                  let statusDict = properties["status"] as? [String: Any] else { return nil }
            return .sessionStatus(sessionID: sessionID, status: parseSessionStatus(statusDict))

        case "session.idle":
            guard let sessionID = properties["sessionID"] as? String else { return nil }
            return .sessionIdle(sessionID: sessionID)

        case "permission.asked":
            return .permissionAsked(parsePermissionRequest(properties))

        case "permission.replied":
            guard let sessionID = properties["sessionID"] as? String,
                  let requestID = properties["requestID"] as? String,
                  let reply = properties["reply"] as? String else { return nil }
            return .permissionReplied(sessionID: sessionID, requestID: requestID, reply: reply)

        case "question.asked":
            return .questionAsked(parseQuestionRequest(properties))

        case "question.replied":
            guard let sessionID = properties["sessionID"] as? String,
                  let requestID = properties["requestID"] as? String else { return nil }
            return .questionReplied(sessionID: sessionID, requestID: requestID)

        case "question.rejected":
            // Treat rejection the same as a reply — both mean the question is no
            // longer pending and should be removed from the UI queue.
            guard let sessionID = properties["sessionID"] as? String,
                  let requestID = properties["requestID"] as? String else { return nil }
            return .questionReplied(sessionID: sessionID, requestID: requestID)

        case "todo.updated":
            guard let sessionID = properties["sessionID"] as? String,
                  let todosArray = properties["todos"] as? [[String: Any]] else { return nil }
            let todos = todosArray.map { parseTodo($0) }
            return .todoUpdated(sessionID: sessionID, todos: todos)

        case "message.part.updated":
            guard let sessionID = properties["sessionID"] as? String,
                  let partDict = properties["part"] as? [String: Any] else { return nil }
            return .messagePartUpdated(sessionID: sessionID, part: parseMessagePart(partDict))

        default:
            return .unknown(type: type)
        }
    }

    // MARK: - JSON → Model Helpers (static for REST polling)

    static func parsePermissionFromREST(_ dict: [String: Any]) -> OCPermissionRequest {
        let metadataRaw = dict["metadata"] as? [String: Any] ?? [:]
        let metadata = metadataRaw.compactMapValues { "\($0)" }

        return OCPermissionRequest(
            id: dict["id"] as? String ?? "",
            sessionID: dict["sessionID"] as? String ?? "",
            permission: dict["permission"] as? String ?? "",
            patterns: dict["patterns"] as? [String] ?? [],
            metadata: metadata,
            always: dict["always"] as? [String] ?? []
        )
    }

    static func parseQuestionFromREST(_ dict: [String: Any]) -> OCQuestionRequest {
        let questionsArray = dict["questions"] as? [[String: Any]] ?? []
        let questions = questionsArray.map { q in
            let options = (q["options"] as? [[String: Any]] ?? []).map { o in
                OCQuestionOption(
                    label: o["label"] as? String ?? "",
                    description: o["description"] as? String ?? ""
                )
            }
            return OCQuestionInfo(
                question: q["question"] as? String ?? "",
                header: q["header"] as? String ?? "",
                options: options,
                multiple: q["multiple"] as? Bool ?? false,
                custom: q["custom"] as? Bool ?? true
            )
        }
        return OCQuestionRequest(
            id: dict["id"] as? String ?? "",
            sessionID: dict["sessionID"] as? String ?? "",
            questions: questions
        )
    }

    // MARK: - JSON → Model Helpers (instance)

    private func parseSession(_ dict: [String: Any]) -> OCSession {
        let timeDict = dict["time"] as? [String: Any] ?? [:]
        let summaryDict = dict["summary"] as? [String: Any]

        return OCSession(
            id: dict["id"] as? String ?? "",
            slug: dict["slug"] as? String ?? "",
            projectID: dict["projectID"] as? String ?? "",
            directory: dict["directory"] as? String ?? "",
            title: dict["title"] as? String ?? "Untitled",
            status: .idle,
            summary: summaryDict.map {
                OCSessionSummary(
                    additions: $0["additions"] as? Int ?? 0,
                    deletions: $0["deletions"] as? Int ?? 0,
                    files: $0["files"] as? Int ?? 0
                )
            },
            timeCreated: Date(timeIntervalSince1970: (timeDict["created"] as? Double ?? 0) / 1000),
            timeUpdated: Date(timeIntervalSince1970: (timeDict["updated"] as? Double ?? 0) / 1000),
            parentID: dict["parentID"] as? String,
            workspaceID: dict["workspaceID"] as? String
        )
    }

    private func parseSessionStatus(_ dict: [String: Any]) -> OCSessionStatus {
        OpenCodeHTTPClient.parseSessionStatus(dict)
    }

    private func parsePermissionRequest(_ dict: [String: Any]) -> OCPermissionRequest {
        let metadataRaw = dict["metadata"] as? [String: Any] ?? [:]
        let metadata = metadataRaw.compactMapValues { "\($0)" }

        return OCPermissionRequest(
            id: dict["id"] as? String ?? "",
            sessionID: dict["sessionID"] as? String ?? "",
            permission: dict["permission"] as? String ?? "",
            patterns: dict["patterns"] as? [String] ?? [],
            metadata: metadata,
            always: dict["always"] as? [String] ?? []
        )
    }

    private func parseQuestionRequest(_ dict: [String: Any]) -> OCQuestionRequest {
        let questionsArray = dict["questions"] as? [[String: Any]] ?? []
        let questions = questionsArray.map { q in
            let options = (q["options"] as? [[String: Any]] ?? []).map { o in
                OCQuestionOption(
                    label: o["label"] as? String ?? "",
                    description: o["description"] as? String ?? ""
                )
            }
            return OCQuestionInfo(
                question: q["question"] as? String ?? "",
                header: q["header"] as? String ?? "",
                options: options,
                multiple: q["multiple"] as? Bool ?? false,
                custom: q["custom"] as? Bool ?? true
            )
        }
        return OCQuestionRequest(
            id: dict["id"] as? String ?? "",
            sessionID: dict["sessionID"] as? String ?? "",
            questions: questions
        )
    }

    private func parseTodo(_ dict: [String: Any]) -> OCTodo {
        OCTodo(
            content: dict["content"] as? String ?? "",
            status: dict["status"] as? String ?? "",
            priority: dict["priority"] as? String ?? ""
        )
    }

    private func parseMessagePart(_ dict: [String: Any]) -> OCMessagePart {
        let stateDict = dict["state"] as? [String: Any]
        var toolState: OCToolState?
        if let stateDict {
            switch stateDict["status"] as? String {
            case "pending": toolState = .pending
            case "running": toolState = .running(title: stateDict["title"] as? String)
            case "completed": toolState = .completed(title: stateDict["title"] as? String, output: stateDict["output"] as? String)
            case "error": toolState = .error(message: nil)
            default: break
            }
        }

        return OCMessagePart(
            id: dict["id"] as? String ?? "",
            sessionID: dict["sessionID"] as? String ?? "",
            messageID: dict["messageID"] as? String ?? "",
            type: dict["type"] as? String ?? "",
            tool: dict["tool"] as? String,
            state: toolState
        )
    }
}
