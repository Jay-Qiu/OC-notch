import Foundation
import os
import SQLite3

private let logger = Logger(subsystem: "com.oc-notch.app", category: "SQLiteReader")

/// Reads OpenCode session data directly from the SQLite database.
/// Used as fallback when the HTTP server is not available (TUI-only sessions).
actor SQLiteReader {
    private let dbPath: String

    init(dbPath: String? = nil) {
        self.dbPath = dbPath ?? Self.defaultDBPath()
    }

    private static func defaultDBPath() -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return home.appendingPathComponent(".local/share/opencode/opencode.db").path
    }

    // MARK: - Sessions

    /// Read all non-archived sessions from the database.
    func readSessions() -> [OCSession] {
        guard let db = openDB() else { return [] }
        defer { sqlite3_close(db) }

        let sql = """
            SELECT id, title, project_id, time_created, time_updated
            FROM session
            WHERE time_archived IS NULL
            ORDER BY time_updated DESC
            """

        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            logger.error("Failed to prepare session query")
            return []
        }
        defer { sqlite3_finalize(stmt) }

        var sessions: [OCSession] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            let id = String(cString: sqlite3_column_text(stmt, 0))
            let title = String(cString: sqlite3_column_text(stmt, 1))
            let projectID = String(cString: sqlite3_column_text(stmt, 2))
            let created = sqlite3_column_int64(stmt, 3)
            let updated = sqlite3_column_int64(stmt, 4)

            let session = OCSession(
                id: id,
                slug: "",
                projectID: projectID,
                directory: "",
                title: title,
                status: .idle,
                summary: nil,
                timeCreated: Date(timeIntervalSince1970: Double(created) / 1000),
                timeUpdated: Date(timeIntervalSince1970: Double(updated) / 1000)
            )
            sessions.append(session)
        }

        logger.info("Read \(sessions.count) sessions from SQLite")
        return sessions
    }

    // MARK: - Todos

    /// Read todos for a specific session.
    func readTodos(sessionID: String) -> [OCTodo] {
        guard let db = openDB() else { return [] }
        defer { sqlite3_close(db) }

        let sql = "SELECT content, status, priority FROM todo WHERE session_id = ? ORDER BY rowid"

        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(stmt) }

        sqlite3_bind_text(stmt, 1, sessionID, -1, nil)

        var todos: [OCTodo] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            let content = String(cString: sqlite3_column_text(stmt, 0))
            let status = String(cString: sqlite3_column_text(stmt, 1))
            let priority = String(cString: sqlite3_column_text(stmt, 2))
            todos.append(OCTodo(content: content, status: status, priority: priority))
        }

        return todos
    }

    // MARK: - Private

    private func openDB() -> OpaquePointer? {
        var db: OpaquePointer?
        let flags = SQLITE_OPEN_READONLY | SQLITE_OPEN_NOMUTEX

        guard sqlite3_open_v2(dbPath, &db, flags, nil) == SQLITE_OK else {
            logger.error("Failed to open database at \(self.dbPath)")
            return nil
        }

        return db
    }
}
