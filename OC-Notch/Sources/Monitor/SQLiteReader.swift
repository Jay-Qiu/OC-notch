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

    func readSessions(directories: [String]) -> [OCSession] {
        guard directories.isEmpty == false else { return [] }
        guard let db = openDB() else { return [] }
        defer { sqlite3_close(db) }

        let placeholders = directories.map { _ in "?" }.joined(separator: ", ")

        // ROW_NUMBER per directory: keep only the most recent session per directory
        // to match running TUI processes to their current session
        let sql = """
            SELECT id, title, project_id, directory, time_created, time_updated,
                   summary_additions, summary_deletions, summary_files
            FROM (
                SELECT *, ROW_NUMBER() OVER (PARTITION BY directory ORDER BY time_updated DESC) as rn
                FROM session
                WHERE time_archived IS NULL
                  AND directory IN (\(placeholders))
            )
            WHERE rn = 1
            ORDER BY time_updated DESC
            """

        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            logger.error("Failed to prepare session query")
            return []
        }
        defer { sqlite3_finalize(stmt) }

        // SQLITE_TRANSIENT tells SQLite to copy the string immediately,
        // which is required because Swift's C-string bridging uses temporary buffers.
        let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        for (index, dir) in directories.enumerated() {
            sqlite3_bind_text(stmt, Int32(index + 1), dir, -1, SQLITE_TRANSIENT)
        }

        var sessions: [OCSession] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            let id = String(cString: sqlite3_column_text(stmt, 0))
            let title = String(cString: sqlite3_column_text(stmt, 1))
            let projectID = String(cString: sqlite3_column_text(stmt, 2))
            let directory = String(cString: sqlite3_column_text(stmt, 3))
            let created = sqlite3_column_int64(stmt, 4)
            let updated = sqlite3_column_int64(stmt, 5)
            let additions = sqlite3_column_type(stmt, 6) != SQLITE_NULL ? Int(sqlite3_column_int64(stmt, 6)) : nil
            let deletions = sqlite3_column_type(stmt, 7) != SQLITE_NULL ? Int(sqlite3_column_int64(stmt, 7)) : nil
            let files = sqlite3_column_type(stmt, 8) != SQLITE_NULL ? Int(sqlite3_column_int64(stmt, 8)) : nil

            var summary: OCSessionSummary?
            if let a = additions, let d = deletions, let f = files {
                summary = OCSessionSummary(additions: a, deletions: d, files: f)
            }

            let session = OCSession(
                id: id,
                slug: "",
                projectID: projectID,
                directory: directory,
                title: title,
                status: .idle,
                summary: summary,
                timeCreated: Date(timeIntervalSince1970: Double(created) / 1000),
                timeUpdated: Date(timeIntervalSince1970: Double(updated) / 1000)
            )
            sessions.append(session)
        }

        logger.notice("Read \(sessions.count) sessions for \(directories.count) directories from SQLite, dirs=\(directories)")
        return sessions
    }

    // MARK: - Activity Detection

    func readBusySessionIDs(activeSessionIDs: Set<String>) -> Set<String> {
        guard activeSessionIDs.isEmpty == false else { return [] }
        guard let db = openDB() else { return [] }
        defer { sqlite3_close(db) }

        let placeholders = activeSessionIDs.map { _ in "?" }.joined(separator: ", ")

        let sql = """
            SELECT session_id
            FROM (
                SELECT session_id,
                       json_extract(data, '$.type') as ptype,
                       ROW_NUMBER() OVER (PARTITION BY session_id ORDER BY time_updated DESC) as rn
                FROM part
                WHERE session_id IN (\(placeholders))
            )
            WHERE rn = 1 AND ptype != 'step-finish'
            """

        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(stmt) }

        let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        for (index, id) in activeSessionIDs.enumerated() {
            sqlite3_bind_text(stmt, Int32(index + 1), id, -1, SQLITE_TRANSIENT)
        }

        var ids = Set<String>()
        while sqlite3_step(stmt) == SQLITE_ROW {
            ids.insert(String(cString: sqlite3_column_text(stmt, 0)))
        }
        return ids
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

        let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        sqlite3_bind_text(stmt, 1, sessionID, -1, SQLITE_TRANSIENT)

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
