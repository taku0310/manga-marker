import Foundation
import SQLite3

final class MangaRepository {
    private let db: DatabaseManager

    init(db: DatabaseManager) {
        self.db = db
    }

    // MARK: - Manga CRUD

    @discardableResult
    func upsertManga(title: String,
                     author: String,
                     publisher: String?,
                     coverImageURL: String?,
                     totalVolumes: Int?) -> Int64? {
        db.sync {
            let now = Date().timeIntervalSince1970
            if let existing = findMangaIdByTitle(title: title) {
                let sql = """
                UPDATE manga SET author = ?, publisher = ?, cover_image_url = COALESCE(?, cover_image_url),
                                 total_volumes = COALESCE(?, total_volumes), updated_at = ?
                WHERE id = ?;
                """
                var stmt: OpaquePointer?
                guard sqlite3_prepare_v2(db.db, sql, -1, &stmt, nil) == SQLITE_OK else { return existing }
                defer { sqlite3_finalize(stmt) }
                bindText(stmt, 1, author)
                bindOptionalText(stmt, 2, publisher)
                bindOptionalText(stmt, 3, coverImageURL)
                bindOptionalInt(stmt, 4, totalVolumes)
                sqlite3_bind_double(stmt, 5, now)
                sqlite3_bind_int64(stmt, 6, existing)
                sqlite3_step(stmt)
                return existing
            } else {
                let sql = """
                INSERT INTO manga (title, author, publisher, cover_image_url, total_volumes, is_completed, created_at, updated_at)
                VALUES (?, ?, ?, ?, ?, 0, ?, ?);
                """
                var stmt: OpaquePointer?
                guard sqlite3_prepare_v2(db.db, sql, -1, &stmt, nil) == SQLITE_OK else { return nil }
                defer { sqlite3_finalize(stmt) }
                bindText(stmt, 1, title)
                bindText(stmt, 2, author)
                bindOptionalText(stmt, 3, publisher)
                bindOptionalText(stmt, 4, coverImageURL)
                bindOptionalInt(stmt, 5, totalVolumes)
                sqlite3_bind_double(stmt, 6, now)
                sqlite3_bind_double(stmt, 7, now)
                guard sqlite3_step(stmt) == SQLITE_DONE else { return nil }
                return sqlite3_last_insert_rowid(db.db)
            }
        }
    }

    func deleteManga(id: Int64) {
        db.sync {
            var stmt: OpaquePointer?
            sqlite3_prepare_v2(db.db, "DELETE FROM manga WHERE id = ?;", -1, &stmt, nil)
            sqlite3_bind_int64(stmt, 1, id)
            sqlite3_step(stmt)
            sqlite3_finalize(stmt)
        }
    }

    func setMangaCompleted(id: Int64, completed: Bool) {
        db.sync {
            var stmt: OpaquePointer?
            sqlite3_prepare_v2(db.db, "UPDATE manga SET is_completed = ?, updated_at = ? WHERE id = ?;", -1, &stmt, nil)
            sqlite3_bind_int(stmt, 1, completed ? 1 : 0)
            sqlite3_bind_double(stmt, 2, Date().timeIntervalSince1970)
            sqlite3_bind_int64(stmt, 3, id)
            sqlite3_step(stmt)
            sqlite3_finalize(stmt)
        }
    }

    func fetchManga(id: Int64) -> Manga? {
        db.sync {
            var stmt: OpaquePointer?
            defer { sqlite3_finalize(stmt) }
            guard sqlite3_prepare_v2(db.db, "SELECT * FROM manga WHERE id = ?;", -1, &stmt, nil) == SQLITE_OK else { return nil }
            sqlite3_bind_int64(stmt, 1, id)
            if sqlite3_step(stmt) == SQLITE_ROW { return readManga(stmt) }
            return nil
        }
    }

    func fetchAllManga() -> [Manga] {
        db.sync {
            var stmt: OpaquePointer?
            defer { sqlite3_finalize(stmt) }
            var result: [Manga] = []
            guard sqlite3_prepare_v2(db.db, "SELECT * FROM manga ORDER BY updated_at DESC;", -1, &stmt, nil) == SQLITE_OK else { return result }
            while sqlite3_step(stmt) == SQLITE_ROW { result.append(readManga(stmt)) }
            return result
        }
    }

    func fetchAllMangaWithProgress() -> [MangaWithProgress] {
        let mangas = fetchAllManga()
        return mangas.map { manga in
            let volumes = fetchVolumes(mangaId: manga.id)
            let read = volumes.filter { $0.isRead }.count
            let next = volumes.first { !$0.isRead }
            let latest = volumes.last
            return MangaWithProgress(
                manga: manga,
                readVolumeCount: read,
                registeredVolumeCount: volumes.count,
                nextUnreadVolume: next,
                latestRegisteredVolume: latest
            )
        }
    }

    private func findMangaIdByTitle(title: String) -> Int64? {
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }
        guard sqlite3_prepare_v2(db.db, "SELECT id FROM manga WHERE title = ? LIMIT 1;", -1, &stmt, nil) == SQLITE_OK else { return nil }
        bindText(stmt, 1, title)
        if sqlite3_step(stmt) == SQLITE_ROW { return sqlite3_column_int64(stmt, 0) }
        return nil
    }

    // MARK: - Volume CRUD

    @discardableResult
    func upsertVolume(mangaId: Int64,
                      volumeNumber: Int,
                      isbn: String?,
                      title: String?,
                      coverImageURL: String?,
                      publishedAt: Date?) -> Int64? {
        db.sync {
            let now = Date().timeIntervalSince1970
            let sql = """
            INSERT INTO volumes (manga_id, volume_number, isbn, title, cover_image_url, published_at, is_read, created_at)
            VALUES (?, ?, ?, ?, ?, ?, 0, ?)
            ON CONFLICT(manga_id, volume_number) DO UPDATE SET
                isbn = COALESCE(excluded.isbn, isbn),
                title = COALESCE(excluded.title, title),
                cover_image_url = COALESCE(excluded.cover_image_url, cover_image_url),
                published_at = COALESCE(excluded.published_at, published_at);
            """
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db.db, sql, -1, &stmt, nil) == SQLITE_OK else { return nil }
            defer { sqlite3_finalize(stmt) }
            sqlite3_bind_int64(stmt, 1, mangaId)
            sqlite3_bind_int(stmt, 2, Int32(volumeNumber))
            bindOptionalText(stmt, 3, isbn)
            bindOptionalText(stmt, 4, title)
            bindOptionalText(stmt, 5, coverImageURL)
            bindOptionalDate(stmt, 6, publishedAt)
            sqlite3_bind_double(stmt, 7, now)
            guard sqlite3_step(stmt) == SQLITE_DONE else { return nil }
            return findVolumeId(mangaId: mangaId, volumeNumber: volumeNumber)
        }
    }

    private func findVolumeId(mangaId: Int64, volumeNumber: Int) -> Int64? {
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }
        guard sqlite3_prepare_v2(db.db, "SELECT id FROM volumes WHERE manga_id = ? AND volume_number = ?;", -1, &stmt, nil) == SQLITE_OK else { return nil }
        sqlite3_bind_int64(stmt, 1, mangaId)
        sqlite3_bind_int(stmt, 2, Int32(volumeNumber))
        if sqlite3_step(stmt) == SQLITE_ROW { return sqlite3_column_int64(stmt, 0) }
        return nil
    }

    func fetchVolumes(mangaId: Int64) -> [Volume] {
        db.sync {
            var stmt: OpaquePointer?
            defer { sqlite3_finalize(stmt) }
            var result: [Volume] = []
            guard sqlite3_prepare_v2(db.db, "SELECT * FROM volumes WHERE manga_id = ? ORDER BY volume_number ASC;", -1, &stmt, nil) == SQLITE_OK else { return result }
            sqlite3_bind_int64(stmt, 1, mangaId)
            while sqlite3_step(stmt) == SQLITE_ROW { result.append(readVolume(stmt)) }
            return result
        }
    }

    func setVolumeRead(id: Int64, read: Bool) {
        db.sync {
            var stmt: OpaquePointer?
            sqlite3_prepare_v2(db.db, "UPDATE volumes SET is_read = ?, read_at = ? WHERE id = ?;", -1, &stmt, nil)
            sqlite3_bind_int(stmt, 1, read ? 1 : 0)
            if read {
                sqlite3_bind_double(stmt, 2, Date().timeIntervalSince1970)
            } else {
                sqlite3_bind_null(stmt, 2)
            }
            sqlite3_bind_int64(stmt, 3, id)
            sqlite3_step(stmt)
            sqlite3_finalize(stmt)
        }
    }

    /// 指定シリーズの全巻を未読に戻す。
    func resetReadStatus(mangaId: Int64) {
        db.sync {
            var stmt: OpaquePointer?
            sqlite3_prepare_v2(db.db, "UPDATE volumes SET is_read = 0, read_at = NULL WHERE manga_id = ?;", -1, &stmt, nil)
            sqlite3_bind_int64(stmt, 1, mangaId)
            sqlite3_step(stmt)
            sqlite3_finalize(stmt)
        }
    }

    func deleteVolume(id: Int64) {
        db.sync {
            var stmt: OpaquePointer?
            sqlite3_prepare_v2(db.db, "DELETE FROM volumes WHERE id = ?;", -1, &stmt, nil)
            sqlite3_bind_int64(stmt, 1, id)
            sqlite3_step(stmt)
            sqlite3_finalize(stmt)
        }
    }

    func volumeExists(isbn: String) -> Bool {
        db.sync {
            var stmt: OpaquePointer?
            defer { sqlite3_finalize(stmt) }
            guard sqlite3_prepare_v2(db.db, "SELECT 1 FROM volumes WHERE isbn = ? LIMIT 1;", -1, &stmt, nil) == SQLITE_OK else { return false }
            bindText(stmt, 1, isbn)
            return sqlite3_step(stmt) == SQLITE_ROW
        }
    }

    // MARK: - Notification log

    func wasNotified(isbn: String) -> Bool {
        db.sync {
            var stmt: OpaquePointer?
            defer { sqlite3_finalize(stmt) }
            sqlite3_prepare_v2(db.db, "SELECT 1 FROM notifications_log WHERE isbn = ? LIMIT 1;", -1, &stmt, nil)
            bindText(stmt, 1, isbn)
            return sqlite3_step(stmt) == SQLITE_ROW
        }
    }

    func markNotified(isbn: String) {
        db.sync {
            var stmt: OpaquePointer?
            sqlite3_prepare_v2(db.db, "INSERT OR REPLACE INTO notifications_log (isbn, notified_at) VALUES (?, ?);", -1, &stmt, nil)
            bindText(stmt, 1, isbn)
            sqlite3_bind_double(stmt, 2, Date().timeIntervalSince1970)
            sqlite3_step(stmt)
            sqlite3_finalize(stmt)
        }
    }

    // MARK: - Row readers

    private func readManga(_ stmt: OpaquePointer?) -> Manga {
        Manga(
            id: sqlite3_column_int64(stmt, 0),
            title: columnText(stmt, 1) ?? "",
            author: columnText(stmt, 2) ?? "",
            publisher: columnText(stmt, 3),
            coverImageURL: columnText(stmt, 4),
            totalVolumes: columnOptionalInt(stmt, 5),
            isCompleted: sqlite3_column_int(stmt, 6) == 1,
            createdAt: Date(timeIntervalSince1970: sqlite3_column_double(stmt, 7)),
            updatedAt: Date(timeIntervalSince1970: sqlite3_column_double(stmt, 8))
        )
    }

    private func readVolume(_ stmt: OpaquePointer?) -> Volume {
        Volume(
            id: sqlite3_column_int64(stmt, 0),
            mangaId: sqlite3_column_int64(stmt, 1),
            volumeNumber: Int(sqlite3_column_int(stmt, 2)),
            isbn: columnText(stmt, 3),
            title: columnText(stmt, 4),
            coverImageURL: columnText(stmt, 5),
            publishedAt: columnOptionalDate(stmt, 6),
            isRead: sqlite3_column_int(stmt, 7) == 1,
            readAt: columnOptionalDate(stmt, 8),
            createdAt: Date(timeIntervalSince1970: sqlite3_column_double(stmt, 9))
        )
    }

    // MARK: - Binding helpers

    private func bindText(_ stmt: OpaquePointer?, _ idx: Int32, _ value: String) {
        sqlite3_bind_text(stmt, idx, value, -1, SQLITE_TRANSIENT)
    }

    private func bindOptionalText(_ stmt: OpaquePointer?, _ idx: Int32, _ value: String?) {
        if let value { sqlite3_bind_text(stmt, idx, value, -1, SQLITE_TRANSIENT) } else { sqlite3_bind_null(stmt, idx) }
    }

    private func bindOptionalInt(_ stmt: OpaquePointer?, _ idx: Int32, _ value: Int?) {
        if let value { sqlite3_bind_int(stmt, idx, Int32(value)) } else { sqlite3_bind_null(stmt, idx) }
    }

    private func bindOptionalDate(_ stmt: OpaquePointer?, _ idx: Int32, _ value: Date?) {
        if let value { sqlite3_bind_double(stmt, idx, value.timeIntervalSince1970) } else { sqlite3_bind_null(stmt, idx) }
    }

    private func columnText(_ stmt: OpaquePointer?, _ idx: Int32) -> String? {
        guard let c = sqlite3_column_text(stmt, idx) else { return nil }
        return String(cString: c)
    }

    private func columnOptionalInt(_ stmt: OpaquePointer?, _ idx: Int32) -> Int? {
        sqlite3_column_type(stmt, idx) == SQLITE_NULL ? nil : Int(sqlite3_column_int(stmt, idx))
    }

    private func columnOptionalDate(_ stmt: OpaquePointer?, _ idx: Int32) -> Date? {
        sqlite3_column_type(stmt, idx) == SQLITE_NULL ? nil : Date(timeIntervalSince1970: sqlite3_column_double(stmt, idx))
    }
}
