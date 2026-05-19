import Foundation

/// 登録済みシリーズの「最新巻+1」をOpenBDから推定する仕組み。
/// 現状OpenBDにはシリーズ検索が無いため、最新巻のISBNを基点に
///   ・JANに含まれるシリーズコードからの推測（出版社により規則性あり）
///   ・将来的にGoogle Books APIや楽天ブックスAPIで補完
/// をする想定の雛形。ここでは登録済みISBN周辺を試行する単純実装。
final class NewReleaseChecker {
    private let repository: MangaRepository
    private let openBDService: OpenBDService
    private let notificationService: NotificationService

    init(repository: MangaRepository, openBDService: OpenBDService, notificationService: NotificationService) {
        self.repository = repository
        self.openBDService = openBDService
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
        guard let latest = volumes.last, let isbn = latest.isbn else { return }

        // ISBN-13は末尾1桁がチェックディジット。下位を変えて隣接候補を生成。
        let candidates = neighborISBNs(of: isbn, depth: 8).filter { $0 != isbn }
        guard !candidates.isEmpty else { return }

        do {
            let books = try await openBDService.fetch(isbns: candidates)
            for book in books {
                guard let pubDate = book.publishedAt, pubDate > latest.publishedAt ?? .distantPast else { continue }
                guard !repository.wasNotified(isbn: book.isbn) else { continue }
                guard !repository.volumeExists(isbn: book.isbn) else { continue }

                let isSameSeries = (book.series ?? book.title).contains(manga.title)
                    || manga.title.contains(book.series ?? book.title)
                guard isSameSeries else { continue }

                let nextVolume = (book.volumeNumber ?? (latest.volumeNumber + 1))
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
        } catch {
            print("New release check failed for \(manga.title): \(error)")
        }
    }

    /// ISBN-13のチェックディジットを再計算しつつ、下位を増分させた候補を生成する。
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
