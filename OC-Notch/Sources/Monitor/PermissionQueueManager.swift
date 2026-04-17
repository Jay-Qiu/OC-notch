import Foundation
import os

private let logger = Logger(subsystem: "com.oc-notch.app", category: "PermissionQueue")

/// Manages a queue of pending permission requests, supporting navigation between them.
@MainActor
@Observable
final class PermissionQueueManager {
    var queue: [OCPermissionRequest] = []
    var currentIndex: Int = 0

    var current: OCPermissionRequest? {
        queue.indices.contains(currentIndex) ? queue[currentIndex] : nil
    }

    var count: Int { queue.count }
    var isEmpty: Bool { queue.isEmpty }

    // MARK: - Queue Management

    func enqueue(_ request: OCPermissionRequest) {
        queue.append(request)
        logger.info("Permission enqueued: \(request.id) (queue size: \(self.queue.count))")
    }

    func remove(requestID: String) {
        queue.removeAll { $0.id == requestID }
        // Adjust index if needed
        if currentIndex >= queue.count {
            currentIndex = max(0, queue.count - 1)
        }
        logger.info("Permission removed: \(requestID) (queue size: \(self.queue.count))")
    }

    func removeAll(forSession sessionID: String) {
        queue.removeAll { $0.sessionID == sessionID }
        if currentIndex >= queue.count {
            currentIndex = max(0, queue.count - 1)
        }
    }

    // MARK: - Navigation

    func next() {
        guard queue.isEmpty == false else { return }
        currentIndex = (currentIndex + 1) % queue.count
    }

    func previous() {
        guard queue.isEmpty == false else { return }
        currentIndex = (currentIndex - 1 + queue.count) % queue.count
    }
}
