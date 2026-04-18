import Foundation
import os

private let logger = Logger(subsystem: "com.oc-notch.app", category: "CompletionDetector")

/// Detects task completion using multiple signals from the OpenCode event stream.
/// Priority order: todo completion > session idle after busy > summary change.
@MainActor
@Observable
final class CompletionDetector {
    /// Tracks per-session state for heuristic detection
    private var sessionStates: [String: SessionActivityState] = [String: SessionActivityState]()

    /// Debounce interval — avoid false positives from brief idle gaps
    private let debounceInterval: TimeInterval = 3.0

    // MARK: - Detection Signals

    /// Signal 1: All todos completed
    func checkTodoCompletion(sessionID: String, todos: [OCTodo]) -> TaskCompletionInfo? {
        guard todos.isEmpty == false else { return nil }

        let allCompleted = todos.allSatisfy { $0.status == "completed" }
        let state = getState(for: sessionID)

        // Only trigger if we haven't already reported this completion
        if allCompleted && state.lastTodoCompletionReported == false {
            sessionStates[sessionID]?.lastTodoCompletionReported = true
            logger.notice("Todo completion detected for session \(sessionID)")
            return TaskCompletionInfo(
                sessionID: sessionID,
                sessionTitle: state.title ?? sessionID,
                summary: todos.last?.content
            )
        }

        // Reset when new todos appear
        if allCompleted == false {
            sessionStates[sessionID]?.lastTodoCompletionReported = false
        }

        return nil
    }

    /// Signal 2: Session transitions from busy → idle
    func checkIdleTransition(sessionID: String, newStatus: OCSessionStatus) -> TaskCompletionInfo? {
        let state = getState(for: sessionID)
        let wasBusy = state.wasBusy

        switch newStatus {
        case .busy:
            sessionStates[sessionID]?.wasBusy = true
            sessionStates[sessionID]?.lastActivityTime = Date()
        case .idle:
            if wasBusy {
                sessionStates[sessionID]?.wasBusy = false
                // Only report if there was meaningful activity (> debounce interval)
                if let lastActivity = state.lastActivityTime,
                   Date().timeIntervalSince(lastActivity) >= debounceInterval {
                    logger.notice("Idle transition detected for session \(sessionID)")
                    return TaskCompletionInfo(
                        sessionID: sessionID,
                        sessionTitle: state.title ?? sessionID
                    )
                }
            }
        case .retry:
            break
        }

        return nil
    }

    /// Signal 3: Session summary appeared or changed (file diffs)
    func checkSummaryChange(sessionID: String, summary: OCSessionSummary?) -> TaskCompletionInfo? {
        let state = getState(for: sessionID)
        guard let summary else { return nil }

        let oldSummary = state.lastSummary
        if oldSummary == nil || oldSummary != summary {
            sessionStates[sessionID]?.lastSummary = summary
            // Summary change alone is weak — only use as enrichment, not primary trigger
            return nil
        }
        return nil
    }

    /// Enrich a completion with summary data if available
    func enrich(_ completion: TaskCompletionInfo, session: OCSession) -> TaskCompletionInfo {
        var enriched = completion
        enriched.sessionTitle = session.title

        if let summary = session.summary {
            enriched.filesChanged = summary.files
            enriched.additions = summary.additions
            enriched.deletions = summary.deletions
        }

        return enriched
    }

    // MARK: - Session Tracking

    func trackSession(id: String, title: String) {
        if sessionStates[id] == nil {
            sessionStates[id] = SessionActivityState()
        }
        sessionStates[id]?.title = title
    }

    func removeSession(id: String) {
        sessionStates.removeValue(forKey: id)
    }

    // MARK: - Private

    private func getState(for sessionID: String) -> SessionActivityState {
        if sessionStates[sessionID] == nil {
            sessionStates[sessionID] = SessionActivityState()
        }
        return sessionStates[sessionID]!
    }
}

// MARK: - Session Activity State

private struct SessionActivityState {
    var title: String?
    var wasBusy: Bool = false
    var lastActivityTime: Date?
    var lastSummary: OCSessionSummary?
    var lastTodoCompletionReported: Bool = false
}
