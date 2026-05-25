import Foundation

/// タイトル/シリーズ検索を提供するサービスの共通インターフェース。
/// OpenBDParsedBook を共通の戻り値型として用いる。
protocol BookSearchService: AnyObject {
    func searchByTitle(_ title: String, maxResults: Int) async throws -> [OpenBDParsedBook]
    func searchSeries(_ seriesName: String, maxResults: Int) async throws -> [OpenBDParsedBook]
    /// シリーズ名から全巻をページネーションで取得し、巻数で重複排除して昇順に返す。
    func searchAllVolumes(seriesName: String) async throws -> [OpenBDParsedBook]
}

extension BookSearchService {
    func searchByTitle(_ title: String) async throws -> [OpenBDParsedBook] {
        try await searchByTitle(title, maxResults: 30)
    }

    func searchSeries(_ seriesName: String) async throws -> [OpenBDParsedBook] {
        try await searchSeries(seriesName, maxResults: 30)
    }
}

/// primary を先に試し、結果が空 or エラーなら fallback に切り替える複合サービス。
/// 例: 楽天Kobo (primary) → Google Books (fallback)。
final class CompositeBookSearchService: BookSearchService {
    private let primary: BookSearchService
    private let fallback: BookSearchService

    init(primary: BookSearchService, fallback: BookSearchService) {
        self.primary = primary
        self.fallback = fallback
    }

    func searchByTitle(_ title: String, maxResults: Int) async throws -> [OpenBDParsedBook] {
        if let results = try? await primary.searchByTitle(title, maxResults: maxResults), !results.isEmpty {
            return results
        }
        return try await fallback.searchByTitle(title, maxResults: maxResults)
    }

    func searchSeries(_ seriesName: String, maxResults: Int) async throws -> [OpenBDParsedBook] {
        if let results = try? await primary.searchSeries(seriesName, maxResults: maxResults), !results.isEmpty {
            return results
        }
        return try await fallback.searchSeries(seriesName, maxResults: maxResults)
    }

    func searchAllVolumes(seriesName: String) async throws -> [OpenBDParsedBook] {
        if let results = try? await primary.searchAllVolumes(seriesName: seriesName), !results.isEmpty {
            return results
        }
        return try await fallback.searchAllVolumes(seriesName: seriesName)
    }
}

/// シリーズ検索結果のフィルタ/集約ユーティリティ。
enum SeriesVolumeFilter {
    /// 検索結果から該当シリーズの巻のみを抽出し、巻数で重複排除 (ISBN 持ちを優先) して昇順に返す。
    static func allVolumes(from books: [OpenBDParsedBook], seriesName: String) -> [OpenBDParsedBook] {
        let target = BookMetadataParser.normalizeTitle(seriesName)
        let filtered = books.filter { matchesSeries($0, target: target) }

        var byVolume: [Int: OpenBDParsedBook] = [:]
        var unnumbered: [OpenBDParsedBook] = []
        for book in filtered {
            guard let v = book.volumeNumber else { unnumbered.append(book); continue }
            if let existing = byVolume[v] {
                if existing.isbn == nil, book.isbn != nil { byVolume[v] = book }
            } else {
                byVolume[v] = book
            }
        }
        let numbered = byVolume.values.sorted { ($0.volumeNumber ?? 0) < ($1.volumeNumber ?? 0) }
        // 巻数付きが取れなければ単巻作品とみなして無番号の結果を返す
        return numbered.isEmpty ? unnumbered : numbered
    }

    /// 検索結果をシリーズ単位に集約し、代表として最小巻 (通常 1 巻) を 1 件ずつ返す。表示順は初出順。
    static func representatives(from books: [OpenBDParsedBook]) -> [OpenBDParsedBook] {
        var groups: [String: OpenBDParsedBook] = [:]
        var order: [String] = []
        for book in books {
            let key = BookMetadataParser.normalizeTitle(book.seriesTitle)
            if let existing = groups[key] {
                if (book.volumeNumber ?? Int.max) < (existing.volumeNumber ?? Int.max) {
                    groups[key] = book
                }
            } else {
                groups[key] = book
                order.append(key)
            }
        }
        return order.compactMap { groups[$0] }
    }

    private static func matchesSeries(_ book: OpenBDParsedBook, target: String) -> Bool {
        let normalized = BookMetadataParser.normalizeTitle(book.seriesTitle)
        return normalized.contains(target) || target.contains(normalized)
    }
}
