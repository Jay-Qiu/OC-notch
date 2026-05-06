import Foundation
import os

private let logger = Logger(subsystem: "com.oc-notch.app", category: "HTTPClient")

/// HTTP client for direct REST calls to an OpenCode instance.
actor OpenCodeHTTPClient {
    let instance: OCInstance
    private let session = URLSession.shared

    init(instance: OCInstance) {
        self.instance = instance
    }

    // MARK: - Request Building

    private func authorizedRequest(_ url: URL) -> URLRequest {
        var request = URLRequest(url: url)
        if let token = OpenCodeAuth.bearerToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        return request
    }

    // MARK: - Health

    func healthCheck() async -> Bool {
        let url = instance.baseURL.appendingPathComponent("global/health")
        do {
            let (data, response) = try await session.data(for: authorizedRequest(url))
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { return false }
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                return json["healthy"] as? Bool ?? false
            }
            return false
        } catch {
            return false
        }
    }

    // MARK: - Sessions

    /// Returns session statuses from the HTTP API. Returns `nil` on request failure
    /// (vs. an empty dictionary when the server responds with no busy sessions).
    func getSessionStatuses() async -> [String: OCSessionStatus]? {
        let url = instance.baseURL.appendingPathComponent("session/status")
        do {
            let (data, response) = try await session.data(for: authorizedRequest(url))
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { return nil }
            guard let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }

            var result: [String: OCSessionStatus] = [:]
            for (sessionID, value) in dict {
                if let statusDict = value as? [String: Any] {
                    result[sessionID] = Self.parseSessionStatus(statusDict)
                }
            }
            return result
        } catch {
            logger.error("Failed to get session statuses: \(error)")
            return nil
        }
    }

    static func parseSessionStatus(_ dict: [String: Any]) -> OCSessionStatus {
        switch dict["type"] as? String {
        case "busy": return .busy
        case "retry":
            return .retry(
                attempt: dict["attempt"] as? Int ?? 0,
                message: dict["message"] as? String ?? "",
                next: Date(timeIntervalSince1970: (dict["next"] as? Double ?? 0) / 1000)
            )
        default: return .idle
        }
    }

    func listSessions() async -> [OCSession] {
        let url = instance.baseURL.appendingPathComponent("session")
        do {
            let (data, response) = try await session.data(for: authorizedRequest(url))
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { return [] }
            guard let dicts = (try? JSONSerialization.jsonObject(with: data) as? [[String: Any]]) else { return [] }
            return dicts.map { SessionMonitorService.parseSessionFromREST($0) }
        } catch {
            logger.error("Failed to list sessions: \(error)")
            return []
        }
    }

    // MARK: - Permission Reply

    /// Returns the pending permissions for this instance, or `nil` if the request failed
    /// (network error, non-200, or unparseable response). A successful empty list is `[]`.
    func listPermissions() async -> [OCPermissionRequest]? {
        let url = instance.baseURL.appendingPathComponent("permission")
        do {
            let (data, response) = try await session.data(for: authorizedRequest(url))
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { return nil }
            guard let dicts = (try? JSONSerialization.jsonObject(with: data) as? [[String: Any]]) else { return nil }
            return dicts.map { OpenCodeSSEClient.parsePermissionFromREST($0) }
        } catch {
            return nil
        }
    }

    /// Returns the pending questions for this instance, or `nil` if the request failed.
    /// A successful empty list is `[]`.
    func listQuestions() async -> [OCQuestionRequest]? {
        let url = instance.baseURL.appendingPathComponent("question")
        do {
            let (data, response) = try await session.data(for: authorizedRequest(url))
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { return nil }
            guard let dicts = (try? JSONSerialization.jsonObject(with: data) as? [[String: Any]]) else { return nil }
            return dicts.map { OpenCodeSSEClient.parseQuestionFromREST($0) }
        } catch {
            return nil
        }
    }

    /// Reply to a permission request via `POST /permission/:id/reply` with body
    /// `{ reply: "once" | "always" | "reject" }` (per OpenCode upstream `permission.ts`).
    func replyPermission(requestID: String, reply: PermissionReply) async throws {
        let url = instance.baseURL
            .appendingPathComponent("permission")
            .appendingPathComponent(requestID)
            .appendingPathComponent("reply")

        var request = authorizedRequest(url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = ["reply": reply.rawValue]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (_, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw HTTPError.invalidResponse
        }

        if http.statusCode >= 400 {
            logger.error("Permission reply failed: HTTP \(http.statusCode)")
            throw HTTPError.serverError(statusCode: http.statusCode)
        }

        logger.notice("Permission \(requestID) replied: \(reply.rawValue)")
    }

    // MARK: - Question Reply

    /// Reply to a question via `POST /question/:id/reply` with body
    /// `{ answers: [[String]] }` — outer array is per question in the request,
    /// inner array is the selected option labels (per OpenCode upstream `question.ts`).
    func replyQuestion(requestID: String, answers: [[String]]) async throws {
        let url = instance.baseURL
            .appendingPathComponent("question")
            .appendingPathComponent(requestID)
            .appendingPathComponent("reply")

        var request = authorizedRequest(url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = ["answers": answers]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (_, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw HTTPError.invalidResponse
        }

        if http.statusCode >= 400 {
            logger.error("Question reply failed: HTTP \(http.statusCode)")
            throw HTTPError.serverError(statusCode: http.statusCode)
        }

        logger.notice("Question \(requestID) replied with \(answers.count) answers")
    }
}

enum HTTPError: Error {
    case invalidResponse
    case serverError(statusCode: Int)
}
