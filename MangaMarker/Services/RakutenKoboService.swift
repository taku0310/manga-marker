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

        let books = try await request(
            queryItems: queryItems(appId: appId, accessKey: accessKey, title: trimmed, hits: maxResults, page: 1)
        )
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
            let items = try await request(
                queryItems: queryItems(appId: appId, accessKey: accessKey, title: trimmed, hits: 30, page: page)
            )
            if items.isEmpty { break }
            collected.append(contentsOf: items)
            if items.count < 30 { break }
        }
        return SeriesVolumeFilter.allVolumes(from: collected, seriesName: trimmed)
    }

    // MARK: - Private

    private func queryItems(appId: String, accessKey: String, title: String, hits: Int, page: Int) -> [URLQueryItem] {
        [
            URLQueryItem(name: "format", value: "json"),
            URLQueryItem(name: "applicationId", value: appId),
            URLQueryItem(name: "accessKey", value: accessKey),
            URLQueryItem(name: "koboGenreId", value: mangaGenreId),
            URLQueryItem(name: "title", value: title),
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
