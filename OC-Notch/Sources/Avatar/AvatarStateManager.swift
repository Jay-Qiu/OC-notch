import Foundation
import os

private let logger = Logger(subsystem: "com.oc-notch.app", category: "AvatarStateManager")

/// Maps session monitor state to avatar animation state.
/// Priority: alert > celebrate > thinking > idle
@MainActor
@Observable
final class AvatarStateManager {
    var currentState: AvatarState = .idle

    private var celebrationTimer: Task<Void, Never>?

    /// Update avatar state based on current session monitor state.
    func update(
        hasPendingPermissions: Bool,
        hasActiveSessions: Bool,
        lastCompletion: TaskCompletionInfo?
    ) {
        let newState: AvatarState

        if hasPendingPermissions {
            newState = .alert
            cancelCelebration()
        } else if let completion = lastCompletion {
            // Celebrate and schedule return to normal
            newState = .celebrate
            scheduleCelebrationEnd(for: completion.sessionID)
        } else if hasActiveSessions {
            newState = .thinking
        } else {
            newState = .idle
        }

        if newState != currentState {
            logger.notice("Avatar state \(String(describing: self.currentState)) → \(String(describing: newState))")
            currentState = newState
        }
    }

    // MARK: - Celebration Timer

    private func scheduleCelebrationEnd(for sessionID: String) {
        cancelCelebration()
        celebrationTimer = Task { @MainActor in
            try? await Task.sleep(for: .seconds(5))
            if currentState == .celebrate {
                currentState = .idle
            }
        }
    }

    private func cancelCelebration() {
        celebrationTimer?.cancel()
        celebrationTimer = nil
    }
}
