import Foundation
import os
import SwiftUI

private let logger = Logger(subsystem: "com.oc-notch.app", category: "SessionMonitor")

/// Central service that monitors all OpenCode instances and aggregates session state.
/// Uses SSE (primary) for instances with HTTP servers, and SQLite (fallback) for TUI-only sessions.
@MainActor
@Observable
final class SessionMonitorService {
    // MARK: - Published State

    var activeSessions: [OCSession] = []
    var pendingPermissions: [OCPermissionRequest] = []
    var pendingQuestions: [OCQuestionRequest] = []
    var lastCompletion: TaskCompletionInfo?
    var opencodePIDCount: Int = 0

    // MARK: - Internal State

    private var instances: [OCInstance] = []
    private var sseClients: [String: OpenCodeSSEClient] = [String: OpenCodeSSEClient]()
    private var httpClients: [String: OpenCodeHTTPClient] = [String: OpenCodeHTTPClient]()
    private let processScanner = ProcessScanner()
    private let sqliteReader = SQLiteReader()
    private let completionDetector = CompletionDetector()

    private var scanTask: Task<Void, Never>?
    private var sseListenTasks: [String: Task<Void, Never>] = [String: Task<Void, Never>]()

    // MARK: - Lifecycle

    func startMonitoring() async {
        logger.notice("Starting session monitoring")

        // Initial scan
        await scanForInstances()

        // Periodic rescan for new/removed instances
        scanTask = Task {
            while Task.isCancelled == false {
                try? await Task.sleep(for: .seconds(10))
                await scanForInstances()
            }
        }
    }

    func stopMonitoring() {
        scanTask?.cancel()
        scanTask = nil
        for (_, task) in sseListenTasks {
            task.cancel()
        }
        sseListenTasks.removeAll()
        for (_, client) in sseClients {
            Task { await client.disconnect() }
        }
        sseClients.removeAll()
        httpClients.removeAll()
    }

    // MARK: - Actions

    func replyPermission(requestID: String, reply: PermissionReply) async {
        // Find which instance owns this permission
        guard let permission = pendingPermissions.first(where: { $0.id == requestID }) else { return }

        // Find an HTTP client for any connected instance
        // (permissions go through the server that sent them)
        if let httpClient = httpClients.values.first {
            do {
                try await httpClient.replyPermission(requestID: requestID, reply: reply)
                // Remove from pending — the SSE event will confirm
                pendingPermissions.removeAll { $0.id == requestID }
            } catch {
                logger.error("Failed to reply permission: \(error)")
            }
        } else {
            logger.warning("No HTTP client available to reply to permission \(permission.id)")
        }
    }

    // MARK: - Instance Discovery

    private func scanForInstances() async {
        let discovered = await processScanner.findInstances()

        // Find new instances
        let existingIDs = Set(instances.map(\.id))
        let newInstances = discovered.filter { existingIDs.contains($0.id) == false }

        // Find removed instances
        let discoveredIDs = Set(discovered.map(\.id))
        let removedIDs = existingIDs.subtracting(discoveredIDs)

        // Clean up removed instances
        for id in removedIDs {
            sseListenTasks[id]?.cancel()
            sseListenTasks.removeValue(forKey: id)
            if let client = sseClients.removeValue(forKey: id) {
                Task { await client.disconnect() }
            }
            httpClients.removeValue(forKey: id)
            completionDetector.removeSession(id: id)
        }

        // Connect to new instances
        for instance in newInstances {
            let httpClient = OpenCodeHTTPClient(instance: instance)
            let isHealthy = await httpClient.healthCheck()

            if isHealthy {
                httpClients[instance.id] = httpClient

                let sseClient = OpenCodeSSEClient(instance: instance)
                sseClients[instance.id] = sseClient

                let eventStream = await sseClient.connect()
                sseListenTasks[instance.id] = Task { [weak self] in
                    for await event in eventStream {
                        await self?.handleEvent(event)
                    }
                }

                logger.notice("Connected to OpenCode instance: \(instance.baseURL)")
            }
        }

        instances = discovered
        let totalPIDs = await processScanner.countProcesses()
        let serverCount = discovered.count
        opencodePIDCount = max(totalPIDs - serverCount, 0)

        let dirs = await processScanner.findActiveDirectories()
        logger.notice("Active directories: \(dirs)")
        if dirs.isEmpty == false {
            let sqliteSessions = await sqliteReader.readSessions(directories: dirs)
            logger.notice("SQLite returned \(sqliteSessions.count) sessions (was \(self.activeSessions.count))")

            var merged: [OCSession] = []
            for var session in sqliteSessions {
                if let existing = activeSessions.first(where: { $0.id == session.id }) {
                    session.status = existing.status
                }
                merged.append(session)
                completionDetector.trackSession(id: session.id, title: session.title)
            }
            activeSessions = merged
        } else {
            activeSessions = []
        }
    }

    // MARK: - Completion Handling

    private func reportCompletion(_ completion: TaskCompletionInfo, sessionID: String) {
        // Enrich with session data if available
        let enriched: TaskCompletionInfo
        if let session = activeSessions.first(where: { $0.id == sessionID }) {
            enriched = completionDetector.enrich(completion, session: session)
        } else {
            enriched = completion
        }

        lastCompletion = enriched

        // Auto-dismiss after 5s
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(5))
            if self.lastCompletion?.sessionID == sessionID {
                self.lastCompletion = nil
            }
        }
    }

    // MARK: - Event Handling

    private func handleEvent(_ event: OCEvent) {
        switch event {
        case .serverConnected:
            logger.notice("SSE: server connected")

        case .sessionCreated(let sessionID, let info):
            if activeSessions.contains(where: { $0.id == sessionID }) == false {
                activeSessions.append(info)
            }
            completionDetector.trackSession(id: sessionID, title: info.title)

        case .sessionUpdated(let sessionID, let info):
            if let index = activeSessions.firstIndex(where: { $0.id == sessionID }) {
                // Preserve status from session.status events
                var updated = info
                updated.status = activeSessions[index].status
                activeSessions[index] = updated
            } else {
                activeSessions.append(info)
            }
            completionDetector.trackSession(id: sessionID, title: info.title)

            // Check if summary changed (weak signal — stored for enrichment)
            _ = completionDetector.checkSummaryChange(sessionID: sessionID, summary: info.summary)

        case .sessionDeleted(let sessionID):
            activeSessions.removeAll { $0.id == sessionID }
            pendingPermissions.removeAll { $0.sessionID == sessionID }
            completionDetector.removeSession(id: sessionID)

        case .sessionStatus(let sessionID, let status):
            if let index = activeSessions.firstIndex(where: { $0.id == sessionID }) {
                activeSessions[index].status = status
            }
            switch status {
            case .busy:
                _ = completionDetector.checkIdleTransition(sessionID: sessionID, newStatus: .busy)
            case .idle:
                if let completion = completionDetector.checkIdleTransition(sessionID: sessionID, newStatus: .idle) {
                    reportCompletion(completion, sessionID: sessionID)
                }
            case .retry:
                break
            }

        case .sessionIdle(let sessionID):
            if let index = activeSessions.firstIndex(where: { $0.id == sessionID }) {
                // Check for idle transition completion via detector
                if let completion = completionDetector.checkIdleTransition(sessionID: sessionID, newStatus: .idle) {
                    reportCompletion(completion, sessionID: sessionID)
                }
                activeSessions[index].status = .idle
            }

        case .permissionAsked(var request):
            // Enrich with session title
            if let session = activeSessions.first(where: { $0.id == request.sessionID }) {
                request.sessionTitle = session.title
            }
            pendingPermissions.append(request)

        case .permissionReplied(_, let requestID, _):
            pendingPermissions.removeAll { $0.id == requestID }

        case .questionAsked(let request):
            pendingQuestions.append(request)

        case .questionReplied(_, let requestID):
            pendingQuestions.removeAll { $0.id == requestID }

        case .todoUpdated(let sessionID, let todos):
            // Use CompletionDetector for todo-based completion
            if let completion = completionDetector.checkTodoCompletion(sessionID: sessionID, todos: todos) {
                reportCompletion(completion, sessionID: sessionID)
            }

        case .messagePartUpdated(let sessionID, let part):
            // Track tool execution state for session status
            if part.type == "tool" {
                switch part.state {
                case .running:
                    if let index = activeSessions.firstIndex(where: { $0.id == sessionID }) {
                        activeSessions[index].status = .busy
                        // Track busy state in detector for idle transition detection
                        _ = completionDetector.checkIdleTransition(sessionID: sessionID, newStatus: .busy)
                    }
                default:
                    break
                }
            }

        case .unknown(let type):
            logger.debug("Unknown event type: \(type)")
        }
    }

    // MARK: - REST JSON Parsing

    nonisolated static func parseSessionFromREST(_ dict: [String: Any]) -> OCSession {
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
}
