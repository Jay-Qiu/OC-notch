import Foundation
import os

private let logger = Logger(subsystem: "com.oc-notch.app", category: "ServerManager")

@MainActor
@Observable
final class OpenCodeServerManager {
    private(set) var port: Int?
    private(set) var isRunning = false

    private let processScanner = ProcessScanner()
    private var pollTask: Task<Void, Never>?

    func start() {
        pollTask = Task {
            while Task.isCancelled == false {
                await discoverServer()
                try? await Task.sleep(for: .seconds(5))
            }
        }
    }

    func stop() {
        pollTask?.cancel()
        pollTask = nil
    }

    // MARK: - Private

    private func discoverServer() async {
        let instances = await processScanner.findInstances()

        if let first = instances.first {
            if port != first.port {
                port = first.port
                isRunning = true
                logger.notice("Discovered OpenCode server on port \(first.port) (PID \(first.pid))")
            }
        } else {
            if isRunning {
                logger.notice("OpenCode server no longer available")
                port = nil
                isRunning = false
            }
        }
    }
}
