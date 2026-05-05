import Foundation

/// Reads the optional `OPENCODE_SERVER_PASSWORD` env var that OpenCode honours
/// for `Authorization: Bearer …`. Unset → no header, unauthenticated mode.
///
/// Note: macOS GUI apps launched from the Dock do **not** inherit `~/.zshrc`
/// env vars. Users who want auth must set the var via `launchctl setenv` (or
/// launch OC-Notch from a terminal with the var exported). Documented in the
/// README.
enum OpenCodeAuth {
    static var bearerToken: String? {
        let value = ProcessInfo.processInfo.environment["OPENCODE_SERVER_PASSWORD"]
        return value?.isEmpty == false ? value : nil
    }
}

/// Tracks the timestamp of the last received SSE frame so a watchdog Task can
/// force-reconnect a stalled stream.
actor HeartbeatWatchdog {
    private var lastEvent: Date = Date()
    private let stalenessSeconds: TimeInterval

    init(stalenessSeconds: TimeInterval) {
        self.stalenessSeconds = stalenessSeconds
    }

    func touch() {
        lastEvent = Date()
    }

    func isStale() -> Bool {
        Date().timeIntervalSince(lastEvent) > stalenessSeconds
    }
}
