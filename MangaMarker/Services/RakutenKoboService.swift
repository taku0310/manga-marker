import Foundation

enum RakutenKoboError: LocalizedError {
    case missingCredentials
    case invalidURL
    case notFound
    case rateLimited
    case http(Int, String?)
    case network(Error)
    case decoding(Error)

    var errorDescription: String? {
        switch self {
        case .missingCredentials:
            return "楽天 API の認証情報が未設定です。Info.plist の RakutenAppId と RakutenAccessKey を設定してください。"
        case .invalidURL: return "URLが不正です"
        case .notFound: return "該当する電子書籍が見つかりませんでした"
        case .rateLimited: return "楽天 API のアクセス制限に達しました。"
        case .http(let code, let detail):
            if let detail, !detail.isEmpty { return "HTTPエラー \(code): \(detail)" }
            return "HTTPエラー: \(code)"
        case .network(let e): return "通信エラー: \(e.localizedDescription)"
        case .decoding(let e): return "データ解析エラー: \(e.localizedDescription)"
        }
    }
}

private struct RakutenKoboAPIErrorBody: Decodable {
    let error: String?
    let errorDescription: String?

    enum CodingKeys: String, CodingKey {
        case error
        case errorDescription = "error_description"
    }

    var displayMessage: String? {
        let parts = [error, errorDescription].compactMap { $0?.isEmpty == false ? $0 : nil }
        return parts.isEmpty ? nil : parts.joined(separator: " - ")
    }
}

/// 楽天Kobo電子書籍検索API クライアント (新 OpenAPI)。
/// マンガの取得件数が Google Books より多い傾向があるため、検索の第一候補に用いる。
///
/// 認証は `applicationId` (UUID) と `accessKey` (`pk_` トークン) の両方が必要で、
/// いずれも `Info.plist` の `RakutenAppId` / `RakutenAccessKey` から `AppConfig` 経由で取得する。
/// 旧ホスト app.rakuten.co.jp は UUID 形式の applicationId を受け付けないため、
/// 新ホスト openapi.rakuten.co.jp を使用する。
/// https://webservice.rakuten.co.jp/documentation/kobo-ebook-search
final class RakutenKoboService: BookSearchService {
    private let session: URLSession
    private let baseURL = URL(string: "https://openapi.rakuten.co.jp/services/api/Kobo/EbookSearch/20170426")!
    private let appId: String?
    private let accessKey: String?

    /// 楽天Kobo の「コミック」ジャンル。マンガに絞り込むため付与する。
    private let mangaGenreId = "101"
    /// 全巻取得時の最大ページ数 (1 ページ最大 30 件 = 最大 180 巻)。
    private let maxPagesForAllVolumes = 6
    /// レート制限 (429) 時の最大リトライ回数。
    private let maxRetriesOnRateLimit = 4
    /// レート制限回避のためのページ間ウェイト (楽天はおよそ 1 req/秒)。
    private let interPageDelayNanos: UInt64 = 800_000_000

    init(session: URLSession = .shared,
         appId: String? = AppConfig.rakutenAppId,
         accessKey: String? = AppConfig.rakutenAccessKey) {
        self.session = session
        self.appId = appId
        self.accessKey = accessKey
    }

    func searchByTitle(_ title: String, maxResults: Int = 30) async throws -> [OpenBDParsedBook] {
        guard let appId, let accessKey else { throw RakutenKoboError.missingCredentials }
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        // まず title 検索 (精度優先)。0 件ならカタカナ読み・別名対応のため keyword 検索へ
        // フォールバック (楽天の検索インデックスが「ハンターハンター」→HUNTER×HUNTER 等を吸収)。
        var books = try await request(
            queryItems: queryItems(appId: appId, accessKey: accessKey, field: .title, value: trimmed, hits: maxResults, page: 1)
        )
        if books.isEmpty {
            books = try await request(
                queryItems: queryItems(appId: appId, accessKey: accessKey, field: .keyword, value: trimmed, hits: maxResults, page: 1)
            )
        }
        return books.sorted { ($0.publishedAt ?? .distantPast) > ($1.publishedAt ?? .distantPast) }
    }

    func searchSeries(_ seriesName: String, maxResults: Int = 30) async throws -> [OpenBDParsedBook] {
        let books = try await searchByTitle(seriesName, maxResults: maxResults)
        let target = BookMetadataParser.normalizeTitle(seriesName)
        return books.filter { book in
            let candidates = [book.series, book.title].compactMap { $0 }
            return candidates.contains { candidate in
                let normalized = BookMetadataParser.normalizeTitle(candidate)
                return normalized.contains(target) || target.contains(normalized)
            }
        }
    }

    func searchAllVolumes(seriesName: String) async throws -> [OpenBDParsedBook] {
        guard let appId, let accessKey else { throw RakutenKoboError.missingCredentials }
        let trimmed = seriesName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        var collected: [OpenBDParsedBook] = []
        for page in 1...maxPagesForAllVolumes {
            let items: [OpenBDParsedBook]
            do {
                items = try await fetchPageWithRetry(appId: appId, accessKey: accessKey, title: trimmed, page: page)
            } catch {
                // 末尾ページ超過の 404/not_found 等は「打ち切り」として扱い、それまでの取得結果を活かす。
                #if DEBUG
                print("[RakutenKobo] searchAllVolumes page \(page) stopped: \(error.localizedDescription)")
                #endif
                break
            }
            if items.isEmpty { break }
            collected.append(contentsOf: items)
            if items.count < 30 { break }
            // 次ページ取得前に小休止してレート制限を避ける
            try? await Task.sleep(nanoseconds: interPageDelayNanos)
        }
        let volumes = SeriesVolumeFilter.allVolumes(from: collected, seriesName: trimmed)
        #if DEBUG
        print("[RakutenKobo] searchAllVolumes(\(trimmed)): collected=\(collected.count) volumes=\(volumes.count)")
        #endif
        return volumes
    }

    /// 1 ページを取得する。レート制限 (429) の場合は指数バックオフでリトライする
    /// (末尾ページ超過などの 404/その他エラーはリトライせず throw)。
    private func fetchPageWithRetry(appId: String, accessKey: String, title: String, page: Int) async throws -> [OpenBDParsedBook] {
        var attempt = 0
        while true {
            do {
                return try await request(
                    queryItems: queryItems(appId: appId, accessKey: accessKey, field: .title, value: title, hits: 30, page: page)
                )
            } catch RakutenKoboError.rateLimited {
                guard attempt < maxRetriesOnRateLimit else { throw RakutenKoboError.rateLimited }
                attempt += 1
                let backoffNanos = UInt64(Double(1 << attempt) * 0.5 * 1_000_000_000) // 1.0, 2.0, 4.0, 8.0s
                #if DEBUG
                print("[RakutenKobo] page \(page) rate limited, retry \(attempt)/\(maxRetriesOnRateLimit)")
                #endif
                try? await Task.sleep(nanoseconds: backoffNanos)
            }
        }
    }

    // MARK: - Private

    /// 検索フィールド。`title` は完全一致寄り、`keyword` は楽天の検索インデックス
    /// (読み仮名・別名を吸収) を使う広い検索。
    private enum SearchField: String {
        case title
        case keyword
    }

    private func queryItems(appId: String, accessKey: String, field: SearchField, value: String, hits: Int, page: Int) -> [URLQueryItem] {
        [
            URLQueryItem(name: "format", value: "json"),
            URLQueryItem(name: "applicationId", value: appId),
            URLQueryItem(name: "accessKey", value: accessKey),
            URLQueryItem(name: "koboGenreId", value: mangaGenreId),
            URLQueryItem(name: field.rawValue, value: value),
            URLQueryItem(name: "hits", value: String(min(max(hits, 1), 30))),
            URLQueryItem(name: "page", value: String(min(max(page, 1), 100)))
        ]
    }

    private func request(queryItems: [URLQueryItem]) async throws -> [OpenBDParsedBook] {
        guard var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else {
            throw RakutenKoboError.invalidURL
        }
        components.queryItems = queryItems
        guard let url = components.url else { throw RakutenKoboError.invalidURL }

        #if DEBUG
        print("[RakutenKobo] GET \(url.absoluteString)")
        #endif

        do {
            let (data, response) = try await session.data(from: url)
            if let http = response as? HTTPURLResponse {
                switch http.statusCode {
                case 200..<300:
                    break
                case 429:
                    throw RakutenKoboError.rateLimited
                case 404:
                    throw RakutenKoboError.notFound
                default:
                    let detail = (try? JSONDecoder().decode(RakutenKoboAPIErrorBody.self, from: data))?.displayMessage
                    #if DEBUG
                    if let body = String(data: data, encoding: .utf8) {
                        print("[RakutenKobo] HTTP \(http.statusCode) body: \(body)")
                    }
                    #endif
                    throw RakutenKoboError.http(http.statusCode, detail)
                }
            }
            let decoded = try JSONDecoder().decode(RakutenKoboResponse.self, from: data)
            return decoded.items.compactMap(\.toParsedBook)
        } catch let e as RakutenKoboError {
            throw e
        } catch let e as DecodingError {
            throw RakutenKoboError.decoding(e)
        } catch {
            throw RakutenKoboError.network(error)
        }
    }
}
