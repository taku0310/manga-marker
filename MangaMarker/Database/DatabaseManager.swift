import Foundation
import SQLite3
import os

let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

final class DatabaseManager: @unchecked Sendable {
    private static let log = Logger(subsystem: "com.example.MangaMarker", category: "Database")
    static let shared = DatabaseManager()

    private(set) var db: OpaquePointer?
    private let queue = DispatchQueue(label: "com.mangamarker.db", qos: .userInitiated)

    private init() {
        open()
        migrate()
    }

    deinit {
        if db != nil { sqlite3_close(db) }
    }

    private var dbPath: String {
        let url = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first!
            .appendingPathComponent("MangaMarker", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url.appendingPathComponent("manga.sqlite").path
    }

    private func open() {
        if sqlite3_open(dbPath, &db) != SQLITE_OK {
            let message = db.map { String(cString: sqlite3_errmsg($0)) } ?? "unknown error"
            // Release でも記録する (assertionFailure は Release で no-op のため)。
            Self.log.error("DB open failed: \(message, privacy: .public)")
            assertionFailure("DB open failed: \(message)")
        }
        exec("PRAGMA foreign_keys = ON;")
        exec("PRAGMA journal_mode = WAL;")
    }

    func sync<T>(_ block: () throws -> T) rethrows -> T {
        try queue.sync(execute: block)
    }

    @discardableResult
    func exec(_ sql: String) -> Bool {
        var err: UnsafeMutablePointer<CChar>?
        let rc = sqlite3_exec(db, sql, nil, nil, &err)
        if rc != SQLITE_OK, let err {
            Self.log.error("SQL error: \(String(cString: err), privacy: .public)")
            sqlite3_free(err)
            return false
        }
        return true
    }

    private func migrate() {
        exec("""
        CREATE TABLE IF NOT EXISTS manga (
            id              INTEGER PRIMARY KEY AUTOINCREMENT,
            title           TEXT    NOT NULL,
            author          TEXT    NOT NULL DEFAULT '',
            publisher       TEXT,
            cover_image_url TEXT,
            total_volumes   INTEGER,
            is_completed    INTEGER NOT NULL DEFAULT 0,
            created_at      REAL    NOT NULL,
            updated_at      REAL    NOT NULL
        );
        """)

        exec("""
        CREATE TABLE IF NOT EXISTS volumes (
            id              INTEGER PRIMARY KEY AUTOINCREMENT,
            manga_id        INTEGER NOT NULL,
            volume_number   INTEGER NOT NULL,
            isbn            TEXT,
            title           TEXT,
            cover_image_url TEXT,
            published_at    REAL,
            is_read         INTEGER NOT NULL DEFAULT 0,
            read_at         REAL,
            created_at      REAL    NOT NULL,
            UNIQUE(manga_id, volume_number),
            FOREIGN KEY(manga_id) REFERENCES manga(id) ON DELETE CASCADE
        );
        """)

        exec("CREATE INDEX IF NOT EXISTS idx_volumes_manga_id ON volumes(manga_id);")
        exec("CREATE INDEX IF NOT EXISTS idx_volumes_isbn ON volumes(isbn);")

        exec("""
        CREATE TABLE IF NOT EXISTS notifications_log (
            isbn        TEXT PRIMARY KEY,
            notified_at REAL NOT NULL
        );
        """)
    }
}
