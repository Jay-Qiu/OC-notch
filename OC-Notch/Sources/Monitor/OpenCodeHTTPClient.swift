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

    // MARK: - Health

    func healthCheck() async -> Bool {
        let url = instance.baseURL.appendingPathComponent("global/health")
        do {
            let (data, response) = try await session.data(from: url)
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

    func listSessions() async -> [OCSession] {
        let url = instance.baseURL.appendingPathComponent("session")
        do {
            let (data, response) = try await session.data(from: url)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { return [] }
            guard let dicts = (try? JSONSerialization.jsonObject(with: data) as? [[String: Any]]) else { return [] }
            return dicts.map { SessionMonitorService.parseSessionFromREST($0) }
        } catch {
            logger.error("Failed to list sessions: \(error)")
            return []
        }
    }

    // MARK: - Permission Reply

    /// Reply to a permission request.
    /// The reply mechanism uses SSE or a specific endpoint. Based on the OpenAPI spec,
    /// permission replies go through the event system. We may need to find the correct
    /// endpoint by inspecting the web client behavior.
    ///
    /// For now, we attempt POST to a permission reply endpoint.
    func replyPermission(requestID: String, reply: PermissionReply) async throws {
        // The OpenAPI spec shows permission.replied event but no explicit REST endpoint
        // for replying. The web UI likely uses a websocket or specific endpoint.
        // We'll need to investigate the actual mechanism.
        //
        // Possible endpoints to try:
        // POST /permission/{requestID}/reply
        // or the reply might go through a different channel

        // Attempt the most likely endpoint pattern
        let url = instance.baseURL
            .appendingPathComponent("permission")
            .appendingPathComponent(requestID)
            .appendingPathComponent("reply")

        var request = URLRequest(url: url)
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
}

enum HTTPError: Error {
    case invalidResponse
    case serverError(statusCode: Int)
}
