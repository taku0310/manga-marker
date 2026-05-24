import Foundation

/// タイトル/シリーズ検索を提供するサービスの共通インターフェース。
/// OpenBDParsedBook を共通の戻り値型として用いる。
protocol BookSearchService: AnyObject {
    func searchByTitle(_ title: String, maxResults: Int) async throws -> [OpenBDParsedBook]
    func searchSeries(_ seriesName: String, maxResults: Int) async throws -> [OpenBDParsedBook]
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
}
