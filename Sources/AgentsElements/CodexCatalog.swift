import Foundation
import SQLite3

/// Codex's own thread catalog.
///
/// Unlike Claude Code, Codex writes no title into the rollout JSONL — the desktop app keeps
/// it in SQLite instead, alongside the git branch. Reading it is what lets a Codex session
/// show the same generated title you see in the app.
///
/// Opened read-only and `immutable=1`: Codex may well be running while we scan, and immutable
/// mode promises we touch neither the database nor its WAL. If anything is off — file missing,
/// schema changed, database busy — the catalog is simply empty and every caller falls back to
/// deriving a title from the transcript, exactly as it would on a machine that never ran the
/// Codex app.
enum CodexCatalog {

    struct Entry {
        let title: String?
        let branch: String?
    }

    static func load() -> [String: Entry] {
        let path = Paths.home.appendingPathComponent(".codex/sqlite/codex-dev.db").path
        guard FileManager.default.fileExists(atPath: path) else { return [:] }

        var db: OpaquePointer?
        let flags = SQLITE_OPEN_READONLY | SQLITE_OPEN_URI
        guard sqlite3_open_v2("file:\(path)?immutable=1", &db, flags, nil) == SQLITE_OK else {
            sqlite3_close(db)
            return [:]
        }
        defer { sqlite3_close(db) }

        var out: [String: Entry] = [:]
        var stmt: OpaquePointer?
        let sql = "SELECT thread_id, display_title, git_branch FROM local_thread_catalog"
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return [:] }
        defer { sqlite3_finalize(stmt) }

        while sqlite3_step(stmt) == SQLITE_ROW {
            guard let idC = sqlite3_column_text(stmt, 0) else { continue }
            let id = String(cString: idC)
            let title = sqlite3_column_text(stmt, 1).map { String(cString: $0) }
            let branch = sqlite3_column_text(stmt, 2).map { String(cString: $0) }
            out[id] = Entry(title: title, branch: branch)
        }
        return out
    }
}
