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
    private let bookSearchService: GoogleBooksService
    private let notificationService: NotificationService

    init(repository: MangaRepository,
         openBDService: OpenBDService,
         bookSearchService: GoogleBooksService,
         notificationService: NotificationService) {
        self.repository = repository
        self.openBDService = openBDService
        self.bookSearchService = bookSearchService
        self.notificationService = notificationService
    }

    func checkAll() async {
        let mangas = repository.fetchAllManga().filter { !$0.isCompleted }
        for manga in mangas {
            await check(manga: manga)
        }
    }

    func check(manga: Manga) async {
        let volumes = repository.fetchVolumes(mangaId: manga.id)

        // Strategy 1: Google Books シリーズ検索
        do {
            let books = try await bookSearchService.searchSeries(manga.title)
            if !books.isEmpty {
                await process(candidates: books, manga: manga, volumes: volumes)
                return
            }
        } catch {
            print("Google Books series search failed for \(manga.title): \(error)")
        }

        // Strategy 2: OpenBD ISBN 近傍
        await fallbackByISBNNeighborhood(manga: manga, volumes: volumes)
    }

    // MARK: - Strategies

    private func process(candidates books: [OpenBDParsedBook], manga: Manga, volumes: [Volume]) async {
        let latestPubDate = volumes.compactMap(\.publishedAt).max() ?? .distantPast
        let latestVolumeNumber = volumes.map(\.volumeNumber).max() ?? 0
        let knownISBNs = Set(volumes.compactMap(\.isbn))
        let knownVolumeNumbers = Set(volumes.map(\.volumeNumber))

        for book in books {
            guard isSameSeries(book: book, manga: manga) else { continue }
            guard !knownISBNs.contains(book.isbn) else { continue }
            guard !repository.wasNotified(isbn: book.isbn) else { continue }

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
                isbn: book.isbn,
                releaseDate: pubDate
            )
            repository.markNotified(isbn: book.isbn)
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
