import Foundation
import os

private let logger = Logger(subsystem: "com.oc-notch.app", category: "QuestionQueue")

@MainActor
@Observable
final class QuestionQueueManager {
    private var sessionOrder: [String] = []
    private var sessionQueues: [String: [OCQuestionRequest]] = [:]
    private var dismissedIDs: Set<String> = []
    private var lastSyncedQuestions: [OCQuestionRequest] = []
    private(set) var dismissedBySession: [String: [OCQuestionRequest]] = [:]

    var activeSessionID: String? { sessionOrder.first }

    var currentQuestion: OCQuestionRequest? {
        guard let id = activeSessionID else { return nil }
        return sessionQueues[id]?.first
    }

    var currentSessionQuestionCount: Int {
        guard let id = activeSessionID else { return 0 }
        return sessionQueues[id]?.count ?? 0
    }

    var waitingSessionCount: Int {
        max(0, sessionOrder.count - 1)
    }

    var isEmpty: Bool { sessionOrder.isEmpty }

    func sync(with questions: [OCQuestionRequest]) {
        lastSyncedQuestions = questions
        rebuildQueues()
    }

    func dismiss(questionID: String) {
        dismissedIDs.insert(questionID)
        rebuildQueues()
        logger.notice("Dismissed question \(questionID)")
    }

    func dismissSession(_ sessionID: String) {
        let ids = sessionQueues[sessionID]?.map(\.id) ?? []
        dismissedIDs.formUnion(ids)
        rebuildQueues()
        logger.notice("Dismissed all questions for session \(sessionID)")
    }

    func resumeSession(_ sessionID: String) {
        let ids = Set(dismissedBySession[sessionID]?.map(\.id) ?? [])
        dismissedIDs.subtract(ids)
        rebuildQueues()
        logger.notice("Resumed session \(sessionID) with \(ids.count) questions")
    }

    func dismissedQuestionCount(for sessionID: String) -> Int {
        dismissedBySession[sessionID]?.count ?? 0
    }

    func hasDismissedQuestions(for sessionID: String) -> Bool {
        (dismissedBySession[sessionID]?.count ?? 0) > 0
    }

    func waitingSessionIDs() -> [String] {
        Array(sessionOrder.dropFirst())
    }

    func questionCount(for sessionID: String) -> Int {
        sessionQueues[sessionID]?.count ?? 0
    }

    private func rebuildQueues() {
        let allIDs = Set(lastSyncedQuestions.map(\.id))
        dismissedIDs = dismissedIDs.intersection(allIDs)

        let dismissed = lastSyncedQuestions.filter { dismissedIDs.contains($0.id) }
        dismissedBySession = Dictionary(grouping: dismissed, by: \.sessionID)

        let active = lastSyncedQuestions.filter { !dismissedIDs.contains($0.id) }
        let grouped = Dictionary(grouping: active, by: \.sessionID)

        for sessionID in grouped.keys where !sessionOrder.contains(sessionID) {
            sessionOrder.append(sessionID)
        }

        let previousActive = activeSessionID
        sessionOrder.removeAll { grouped[$0] == nil }
        sessionQueues = grouped

        if let newActive = activeSessionID, newActive != previousActive {
            logger.notice("Auto-transition to session \(newActive) (queue: \(self.sessionOrder.count) sessions)")
        }
    }
}
