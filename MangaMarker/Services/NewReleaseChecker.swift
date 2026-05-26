import Foundation

/// 登録済みシリーズの新刊を検出する。
///
/// 戦略:
/// 1) Google Books API でシリーズ名検索 → 同一シリーズと判定できた書籍を比較。
/// 2) Google Books が一件もヒットしない場合のフォールバックとして、
///    OpenBD で「最新巻 ISBN の近傍」を試行。
/// いずれの経路でも、最終的に「未登録 ISBN かつ 最新登録巻より新しい発売日」のみを採用し、
/// `notifications_log` で冪等性を担保する。
final class NewReleaseChecker {
    private let repository: MangaRepository
    private let openBDService: OpenBDService
    private let bookSearchService: BookSearchService
    private let notificationService: NotificationService

    private let defaults = UserDefaults.standard
    /// 同一シリーズの再チェック間隔。短時間に何度も画面を開いても API を叩きすぎないようにする。
    private let minCheckInterval: TimeInterval = 6 * 60 * 60 // 6h

    init(repository: MangaRepository,
         openBDService: OpenBDService,
         bookSearchService: BookSearchService,
         notificationService: NotificationService) {
        self.repository = repository
        self.openBDService = openBDService
        self.bookSearchService = bookSearchService
        self.notificationService = notificationService
    }

    /// 最終チェック時刻 (UNIX time)。未チェックは 0。最も古いものから処理する並べ替えに使う。
    func lastChecked(_ mangaId: Int64) -> TimeInterval {
        defaults.double(forKey: lastCheckedKey(mangaId))
    }

    func checkAll(force: Bool = false) async {
        let mangas = repository.fetchAllManga().filter { !$0.isCompleted }
        for manga in mangas {
            await check(manga: manga, force: force)
        }
    }

    /// 指定シリーズの新刊をチェックする。
    /// - Parameter force: true で再チェック間隔を無視して必ず実行 (Pull to Refresh 等)。
    /// - Returns: 実際にチェックを行ったら true (間隔内でスキップした場合は false)。
    @discardableResult
    func check(manga: Manga, force: Bool = false) async -> Bool {
        guard force || isStale(manga.id) else { return false }

        let volumes = repository.fetchVolumes(mangaId: manga.id)

        // Strategy 1: オンライン書誌検索 (楽天Kobo → Google Books フォールバック)
        do {
            let books = try await bookSearchService.searchSeries(manga.title)
            if !books.isEmpty {
                await process(candidates: books, manga: manga, volumes: volumes)
                markChecked(manga.id)
                return true
            }
        } catch {
            print("Series search failed for \(manga.title): \(error)")
        }

        // Strategy 2: OpenBD ISBN 近傍
        await fallbackByISBNNeighborhood(manga: manga, volumes: volumes)
        markChecked(manga.id)
        return true
    }

    // MARK: - Throttle

    private func isStale(_ mangaId: Int64) -> Bool {
        let last = lastChecked(mangaId)
        return last == 0 || Date().timeIntervalSince1970 - last >= minCheckInterval
    }

    private func markChecked(_ mangaId: Int64) {
        defaults.set(Date().timeIntervalSince1970, forKey: lastCheckedKey(mangaId))
    }

    private func lastCheckedKey(_ mangaId: Int64) -> String { "newrelease.lastChecked.\(mangaId)" }

    // MARK: - Strategies

    private func process(candidates books: [OpenBDParsedBook], manga: Manga, volumes: [Volume]) async {
        let latestPubDate = volumes.compactMap(\.publishedAt).max() ?? .distantPast
        let latestVolumeNumber = volumes.map(\.volumeNumber).max() ?? 0
        let knownISBNs = Set(volumes.compactMap(\.isbn))
        let knownVolumeNumbers = Set(volumes.map(\.volumeNumber))

        for book in books {
            guard isSameSeries(book: book, manga: manga) else { continue }

            // ISBN が無いソース (楽天Kobo 等) では book.id を冪等キーに使う。
            let dedupKey = book.isbn ?? book.id
            if let isbn = book.isbn, knownISBNs.contains(isbn) { continue }
            guard !repository.wasNotified(isbn: dedupKey) else { continue }

            // 発売日が最新巻より新しい必要がある (発売日不明の場合は採用しない)
            guard let pubDate = book.publishedAt, pubDate > latestPubDate else { continue }

            // 巻数が既知の番号と被るなら、同じ巻の別装版 (廉価版・愛蔵版等) の可能性が高いのでスキップ
            let nextVolume: Int
            if let bookVolume = book.volumeNumber {
                if knownVolumeNumbers.contains(bookVolume) { continue }
                nextVolume = bookVolume
            } else {
                nextVolume = latestVolumeNumber + 1
            }

            repository.upsertVolume(
                mangaId: manga.id,
                volumeNumber: nextVolume,
                isbn: book.isbn,
                title: book.title,
                coverImageURL: book.coverImageURL,
                publishedAt: pubDate
            )
            await notificationService.scheduleNewReleaseNotification(
                mangaTitle: manga.title,
                volumeNumber: nextVolume,
                isbn: dedupKey,
                releaseDate: pubDate
            )
            repository.markNotified(isbn: dedupKey)
        }
    }

    private func fallbackByISBNNeighborhood(manga: Manga, volumes: [Volume]) async {
        guard let latest = volumes.last, let isbn = latest.isbn else { return }
        let candidates = neighborISBNs(of: isbn, depth: 8).filter { $0 != isbn }
        guard !candidates.isEmpty else { return }
        do {
            let books = try await openBDService.fetch(isbns: candidates)
            await process(candidates: books, manga: manga, volumes: volumes)
        } catch {
            print("OpenBD neighborhood check failed for \(manga.title): \(error)")
        }
    }

    // MARK: - Helpers

    private func isSameSeries(book: OpenBDParsedBook, manga: Manga) -> Bool {
        let target = BookMetadataParser.normalizeTitle(manga.title)
        let candidates = [book.series, book.title].compactMap { $0 }
        return candidates.contains { candidate in
            let normalized = BookMetadataParser.normalizeTitle(candidate)
            return normalized.contains(target) || target.contains(normalized)
        }
    }

    private func neighborISBNs(of isbn: String, depth: Int) -> [String] {
        let digits = isbn.filter(\.isNumber)
        guard digits.count == 13 else { return [] }
        let body = String(digits.prefix(12))
        guard let bodyNum = Int(body) else { return [] }

        var result: [String] = []
        for delta in 1...depth {
            let nextBody = String(format: "%012d", bodyNum + delta)
            let check = isbn13CheckDigit(prefix12: nextBody)
            result.append(nextBody + String(check))
        }
        return result
    }

    private func isbn13CheckDigit(prefix12: String) -> Int {
        var sum = 0
        for (i, ch) in prefix12.enumerated() {
            guard let n = Int(String(ch)) else { return 0 }
            sum += (i % 2 == 0) ? n : n * 3
        }
        let mod = sum % 10
        return mod == 0 ? 0 : 10 - mod
    }
}
