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

        // 数字の巻が一つも取れない場合:
        // 上/中/下・前/後編の分冊作品なら順序を連番に割り当てる。それも無ければ単巻作品として返す。
        if byVolume.isEmpty {
            return assignOrdinalVolumes(unnumbered) ?? unnumbered
        }

        // 1 巻のタイトルに巻数が付かない作品 (例: "ワンナイト・モーニング" = 1巻、以降 "... 2".."15") に対応。
        // 無番号のうち「タイトルがシリーズ名と完全一致＝実質1巻」を、1 巻が欠けていれば補完する
        // (ガイドブック等の余分な語が付くものは対象外なので誤登録しない)。
        if byVolume[1] == nil,
           let baseVolume = unnumbered.first(where: { BookMetadataParser.normalizeTitle($0.seriesTitle) == target }) {
            byVolume[1] = baseVolume.withVolumeNumber(1)
        }

        return byVolume.values.sorted { ($0.volumeNumber ?? 0) < ($1.volumeNumber ?? 0) }
    }

    /// 上/中/下・前/後編の分冊を順序に従って 1,2,3… の連番に割り当てる。
    /// 2 冊以上が順序を持つ場合のみ採用 (順序を持たない本＝ガイドブック等は除外)。割り当て不可なら nil。
    private static func assignOrdinalVolumes(_ books: [OpenBDParsedBook]) -> [OpenBDParsedBook]? {
        let ranked = books.compactMap { book -> (rank: Int, book: OpenBDParsedBook)? in
            guard let rank = BookMetadataParser.volumeOrdinal(from: book.title) else { return nil }
            return (rank, book)
        }
        guard ranked.count >= 2 else { return nil }

        var result: [OpenBDParsedBook] = []
        var seenRanks = Set<Int>()
        var number = 1
        for entry in ranked.sorted(by: { $0.rank < $1.rank }) {
            guard seenRanks.insert(entry.rank).inserted else { continue } // 同一順位 (上が2冊等) は1冊に
            result.append(entry.book.withVolumeNumber(number))
            number += 1
        }
        return result
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
