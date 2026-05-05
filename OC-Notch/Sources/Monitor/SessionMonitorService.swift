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

    /// Recently replied question IDs with expiry timestamps.
    /// Prevents poll from re-adding questions that were just answered but not yet processed server-side.
    private var recentlyRepliedQuestions: [String: Date] = [:]

    /// Recently replied permission IDs with expiry timestamps.
    private var recentlyRepliedPermissions: [String: Date] = [:]

    /// Maps sessionID → instanceID for routing replies to the correct HTTP client.
    private var sessionToInstance: [String: String] = [:]

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
                try? await Task.sleep(for: .seconds(3))
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
        guard let permission = pendingPermissions.first(where: { $0.id == requestID }) else { return }

        let httpClient = httpClientForSession(permission.sessionID) ?? httpClients.values.first
        guard let httpClient else {
            logger.warning("No HTTP client available to reply to permission \(permission.id)")
            return
        }

        recentlyRepliedPermissions[requestID] = Date().addingTimeInterval(30)
        do {
            try await httpClient.replyPermission(requestID: requestID, reply: reply)
            pendingPermissions.removeAll { $0.id == requestID }
        } catch {
            recentlyRepliedPermissions.removeValue(forKey: requestID)
            logger.error("Failed to reply permission: \(error)")
        }
    }

    func replyQuestion(requestID: String, answers: [[String]]) async {
        guard let question = pendingQuestions.first(where: { $0.id == requestID }) else { return }

        let httpClient = httpClientForSession(question.sessionID) ?? httpClients.values.first
        guard let httpClient else {
            logger.warning("No HTTP client available to reply to question \(requestID)")
            return
        }

        recentlyRepliedQuestions[requestID] = Date().addingTimeInterval(30)
        do {
            try await httpClient.replyQuestion(requestID: requestID, answers: answers)
            pendingQuestions.removeAll { $0.id == requestID }
        } catch {
            recentlyRepliedQuestions.removeValue(forKey: requestID)
            logger.error("Failed to reply question: \(error)")
        }
    }

    private func httpClientForSession(_ sessionID: String) -> OpenCodeHTTPClient? {
        guard let instanceID = sessionToInstance[sessionID] else { return nil }
        return httpClients[instanceID]
    }

    /// Returns the PID of the OpenCode instance that owns the given session, if known.
    func pidForSession(_ sessionID: String) -> Int32? {
        if let instanceID = sessionToInstance[sessionID] {
            return instances.first(where: { $0.id == instanceID })?.pid
        }

        guard let session = activeSessions.first(where: { $0.id == sessionID }) else { return nil }
        let sameDirInstances = instances.filter { $0.directory == session.directory }
        guard sameDirInstances.isEmpty == false else { return nil }
        if sameDirInstances.count == 1 { return sameDirInstances[0].pid }

        // Distribute unmapped sessions across same-dir instances deterministically.
        // Each unmapped session gets a different instance by index position.
        let unmappedSameDirSessions = activeSessions
            .filter { $0.directory == session.directory && sessionToInstance[$0.id] == nil }
            .sorted(by: { $0.id < $1.id })

        let sessionIndex = unmappedSameDirSessions.firstIndex(where: { $0.id == sessionID }) ?? 0
        return sameDirInstances[sessionIndex % sameDirInstances.count].pid
    }

    func terminalTabForSession(_ sessionID: String) -> TerminalTab? {
        if let instanceID = sessionToInstance[sessionID] {
            return instances.first(where: { $0.id == instanceID })?.terminalTab
        }

        guard let session = activeSessions.first(where: { $0.id == sessionID }) else { return nil }
        let sameDirInstances = instances.filter { $0.directory == session.directory }
        guard sameDirInstances.isEmpty == false else { return nil }
        if sameDirInstances.count == 1 { return sameDirInstances[0].terminalTab }

        let unmappedSameDirSessions = activeSessions
            .filter { $0.directory == session.directory && sessionToInstance[$0.id] == nil }
            .sorted(by: { $0.id < $1.id })

        let sessionIndex = unmappedSameDirSessions.firstIndex(where: { $0.id == sessionID }) ?? 0
        return sameDirInstances[sessionIndex % sameDirInstances.count].terminalTab
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
            sessionToInstance = sessionToInstance.filter { $0.value != id }
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
                        await self?.handleEvent(event, fromInstance: instance.id)
                    }
                }

                // Seed sessionToInstance from status endpoint for busy/retry sessions.
                // Idle sessions will be mapped later when SSE events arrive.
                if let statuses = await httpClient.getSessionStatuses() {
                    for (sessionID, status) in statuses {
                        // Busy/retry status is instance-specific (in-memory state).
                        // Map these sessions to the instance that owns them.
                        switch status {
                        case .busy, .retry:
                            sessionToInstance[sessionID] = instance.id
                        case .idle:
                            break
                        }
                        if let index = activeSessions.firstIndex(where: { $0.id == sessionID }) {
                            activeSessions[index].status = status
                        }
                    }
                }

                logger.notice("Connected to OpenCode instance: \(instance.baseURL)")
            }
        }

        instances = discovered

        let terminalTabs = await TerminalTabProbe.snapshot()
        for i in instances.indices {
            guard let instanceTTY = instances[i].tty else { continue }
            instances[i].terminalTab = terminalTabs.first(where: { $0.tty == instanceTTY })
        }

        let totalPIDs = await processScanner.countProcesses()
        let serverCount = discovered.count
        opencodePIDCount = max(totalPIDs - serverCount, 0)

        let dirs = await processScanner.findActiveDirectories()
        logger.notice("Active directories: \(dirs)")
        if dirs.isEmpty == false {
            let sqliteSessions = await sqliteReader.readSessions(directories: dirs)
            logger.notice("SQLite returned \(sqliteSessions.count) sessions (was \(self.activeSessions.count))")

            // Detect busy sessions from SQLite for TUI-only sessions without SSE
            let sqliteSessionIDs = Set(sqliteSessions.map(\.id))
            let busyIDs = await sqliteReader.readBusySessionIDs(activeSessionIDs: sqliteSessionIDs)

            var httpStatuses: [String: OCSessionStatus] = [:]
            var httpResponded = false
            for (instanceID, httpClient) in httpClients {
                if let statuses = await httpClient.getSessionStatuses() {
                    httpResponded = true
                    for (sessionID, status) in statuses {
                        switch status {
                        case .busy, .retry:
                            sessionToInstance[sessionID] = instanceID
                        case .idle:
                            break
                        }
                    }
                    httpStatuses.merge(statuses) { _, new in new }
                }
            }

            var merged: [OCSession] = []
            for var session in sqliteSessions {
                if let httpStatus = httpStatuses[session.id] {
                    // HTTP authoritative: use whatever the server reports.
                    session.status = httpStatus
                } else if httpResponded {
                    // At least one HTTP server responded but did NOT include this
                    // session in its statuses. Trust HTTP — the session is idle.
                    // We deliberately ignore SQLite's `busyIDs` heuristic here
                    // because it flags any session whose last `part` row isn't
                    // `step-finish` as busy, which leaves sessions stuck in
                    // "Working" indefinitely after a prompt completes.
                    // session.status stays at SQLite default (.idle).
                    _ = session
                } else if let existing = activeSessions.first(where: { $0.id == session.id }) {
                    // No HTTP server responded at all (pure TUI mode or all
                    // instances down). Preserve previously known status.
                    session.status = existing.status
                } else if busyIDs.contains(session.id) {
                    // Brand-new session, no HTTP, no prior state — fall back to
                    // SQLite hint as a best-effort signal.
                    session.status = .busy
                }
                merged.append(session)
                completionDetector.trackSession(id: session.id, title: session.title)
            }
            activeSessions = merged
        } else {
            activeSessions = []
        }

        await pollPermissionsAndQuestions()
    }

    // MARK: - REST Polling (Permissions & Questions)

    /// Reconciles `pendingPermissions` / `pendingQuestions` with the REST snapshot
    /// from each HTTP instance, **without** discarding entries that were populated
    /// via SSE but aren't (yet / no longer) listed by the REST endpoint.
    ///
    /// Per-instance merge:
    ///  - If an instance's GET succeeds, items mapped to that instance that are
    ///    absent from the response are treated as resolved and dropped, and any
    ///    new items in the response are appended.
    ///  - If an instance's GET fails (returns nil), nothing is dropped for that
    ///    instance — SSE-populated state is preserved.
    ///
    /// This avoids the previous "every poll wipes pendingPermissions/Questions"
    /// behaviour, which made requests invisible whenever the REST endpoint
    /// returned an empty list or failed.
    private func pollPermissionsAndQuestions() async {
        var permResponses: [String: [OCPermissionRequest]] = [:]
        var questionResponses: [String: [OCQuestionRequest]] = [:]

        for (instanceID, httpClient) in httpClients {
            if let perms = await httpClient.listPermissions() {
                permResponses[instanceID] = perms
                for p in perms { sessionToInstance[p.sessionID] = instanceID }
            }
            if let questions = await httpClient.listQuestions() {
                questionResponses[instanceID] = questions
                for q in questions { sessionToInstance[q.sessionID] = instanceID }
            }
        }

        var newPermissions = pendingPermissions
        for (instanceID, perms) in permResponses {
            let respIDs = Set(perms.map(\.id))
            // Drop locally-known items owned by this instance that are absent
            // from its fresh response (resolved server-side).
            newPermissions.removeAll { perm in
                sessionToInstance[perm.sessionID] == instanceID && respIDs.contains(perm.id) == false
            }
            // Append any items the server reports that we don't have yet.
            let known = Set(newPermissions.map(\.id))
            for var perm in perms where known.contains(perm.id) == false {
                if let session = activeSessions.first(where: { $0.id == perm.sessionID }) {
                    perm.sessionTitle = session.title
                }
                newPermissions.append(perm)
            }
        }

        var newQuestions = pendingQuestions
        for (instanceID, questions) in questionResponses {
            let respIDs = Set(questions.map(\.id))
            newQuestions.removeAll { q in
                sessionToInstance[q.sessionID] == instanceID && respIDs.contains(q.id) == false
            }
            let known = Set(newQuestions.map(\.id))
            for q in questions where known.contains(q.id) == false {
                newQuestions.append(q)
            }
        }

        let now = Date()
        recentlyRepliedQuestions = recentlyRepliedQuestions.filter { $0.value > now }
        recentlyRepliedPermissions = recentlyRepliedPermissions.filter { $0.value > now }

        pendingPermissions = newPermissions.filter { recentlyRepliedPermissions[$0.id] == nil }
        pendingQuestions = newQuestions.filter { recentlyRepliedQuestions[$0.id] == nil }
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

    private func handleEvent(_ event: OCEvent, fromInstance instanceID: String) {
        switch event {
        case .serverConnected:
            logger.notice("SSE: server connected")

        case .sessionCreated(let sessionID, let info):
            // Don't map sessionToInstance here — shared SQLite means any instance
            // can emit session.created for sessions it doesn't own.
            // Ownership is established by busy/retry status or permission/question events.
            if activeSessions.contains(where: { $0.id == sessionID }) == false {
                activeSessions.append(info)
            }
            completionDetector.trackSession(id: sessionID, title: info.title)

        case .sessionUpdated(let sessionID, let info):
            // Don't map sessionToInstance — same reason as sessionCreated.
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
            sessionToInstance.removeValue(forKey: sessionID)
            completionDetector.removeSession(id: sessionID)

        case .sessionStatus(let sessionID, let status):
            switch status {
            case .busy, .retry:
                sessionToInstance[sessionID] = instanceID
            case .idle:
                // Keep the mapping — session still belongs to this instance.
                // Cleared only when instance dies or session is deleted.
                break
            }
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
            sessionToInstance[request.sessionID] = instanceID
            if let session = activeSessions.first(where: { $0.id == request.sessionID }) {
                request.sessionTitle = session.title
            }
            if pendingPermissions.contains(where: { $0.id == request.id }) == false {
                pendingPermissions.append(request)
            }

        case .permissionReplied(_, let requestID, _):
            pendingPermissions.removeAll { $0.id == requestID }

        case .questionAsked(let request):
            sessionToInstance[request.sessionID] = instanceID
            if pendingQuestions.contains(where: { $0.id == request.id }) == false {
                pendingQuestions.append(request)
            }

        case .questionReplied(_, let requestID):
            pendingQuestions.removeAll { $0.id == requestID }
            recentlyRepliedQuestions[requestID] = Date().addingTimeInterval(30)

        case .todoUpdated(let sessionID, let todos):
            // Use CompletionDetector for todo-based completion
            if let completion = completionDetector.checkTodoCompletion(sessionID: sessionID, todos: todos) {
                reportCompletion(completion, sessionID: sessionID)
            }

        case .messagePartUpdated:
            // Session busy/idle is driven exclusively by session.status SSE events.
            // Individual tool execution states are not reliable indicators of prompt computation.
            break

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
