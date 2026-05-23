import Foundation

enum RakutenError: LocalizedError {
    case missingAppId
    case invalidURL
    case notFound
    case rateLimited
    case http(Int, String?)
    case network(Error)
    case decoding(Error)

    var errorDescription: String? {
        switch self {
        case .missingAppId:
            return "楽天 API の Application ID が設定されていません。Info.plist の RakutenAppId を設定してください。"
        case .invalidURL:
            return "URLが不正です"
        case .notFound:
            return "該当する書籍が見つかりませんでした"
        case .rateLimited:
            return "アクセス制限に達しました。しばらく待ってから再試行してください。"
        case .http(let code, let detail):
            if let detail, !detail.isEmpty {
                if detail.localizedCaseInsensitiveContains("applicationid") {
                    return "applicationId が無効です。Info.plist の RakutenAppId に楽天ウェブサービスのダッシュボードに表示される値を設定してください。アプリケーションID (UUID) で 400 が返る場合は、同ページの「アクセスキー」(目玉アイコンで表示できる秘密トークン) を試してください。"
                }
                return "HTTPエラー \(code): \(detail)"
            }
            return "HTTPエラー: \(code)"
        case .network(let e):
            return "通信エラー: \(e.localizedDescription)"
        case .decoding(let e):
            return "データ解析エラー: \(e.localizedDescription)"
        }
    }
}

/// 楽天ブックス API のエラーレスポンス。
/// 例: `{"error":"wrong_parameter","error_description":"param missing. (booksGenreId)"}`
private struct RakutenAPIErrorBody: Decodable {
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

/// 楽天ブックス書籍検索 API。タイトル検索とシリーズ検索を担当。
/// https://webservice.rakuten.co.jp/documentation/books-book-search
final class RakutenBooksService {
    private let session: URLSession
    private let baseURL = URL(string: "https://app.rakuten.co.jp/services/api/BooksBook/Search/20170404")!
    private let appId: String?

    init(session: URLSession = .shared, appId: String? = AppConfig.rakutenAppId) {
        self.session = session
        self.appId = appId
    }

    /// タイトル/著者/キーワードでのフリーテキスト検索。
    /// ジャンル絞り込みは行わず (API バージョン依存で 400 を返すため)、
    /// 並べ替えはクライアント側で発売日降順に行う。
    func searchByTitle(_ title: String, hits: Int = 30, page: Int = 1) async throws -> [OpenBDParsedBook] {
        guard let appId else { throw RakutenError.missingAppId }
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        let queryItems: [URLQueryItem] = [
            URLQueryItem(name: "applicationId", value: appId),
            URLQueryItem(name: "title", value: trimmed),
            URLQueryItem(name: "hits", value: String(min(max(hits, 1), 30))),
            URLQueryItem(name: "page", value: String(max(page, 1))),
            URLQueryItem(name: "formatVersion", value: "2")
        ]

        let books = try await request(queryItems: queryItems)
        return books.sorted {
            ($0.publishedAt ?? .distantPast) > ($1.publishedAt ?? .distantPast)
        }
    }

    /// シリーズ名から新刊候補を取得する。新刊検出専用。
    /// 楽天 API には `title` と `seriesName` を同時に絞る公式手段が無いため、
    /// `title` フィールド検索 + クライアント側で seriesName 一致フィルタを行う。
    func searchSeries(_ seriesName: String, hits: Int = 30) async throws -> [OpenBDParsedBook] {
        let books = try await searchByTitle(seriesName, hits: hits, page: 1)
        let normalizedTarget = BookMetadataParser.normalizeTitle(seriesName)
        return books.filter { book in
            let candidates = [book.series, book.title].compactMap { $0 }
            return candidates.contains { candidate in
                let normalized = BookMetadataParser.normalizeTitle(candidate)
                return normalized.contains(normalizedTarget) || normalizedTarget.contains(normalized)
            }
        }
    }

    // MARK: - Private

    private func request(queryItems: [URLQueryItem]) async throws -> [OpenBDParsedBook] {
        guard var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else {
            throw RakutenError.invalidURL
        }
        components.queryItems = queryItems
        guard let url = components.url else { throw RakutenError.invalidURL }

        #if DEBUG
        print("[Rakuten] GET \(url.absoluteString)")
        #endif

        do {
            let (data, response) = try await session.data(from: url)
            if let http = response as? HTTPURLResponse {
                switch http.statusCode {
                case 200..<300:
                    break
                case 429:
                    throw RakutenError.rateLimited
                case 404:
                    throw RakutenError.notFound
                default:
                    let detail = (try? JSONDecoder().decode(RakutenAPIErrorBody.self, from: data))?.displayMessage
                    #if DEBUG
                    if let body = String(data: data, encoding: .utf8) {
                        print("[Rakuten] HTTP \(http.statusCode) body: \(body)")
                    }
                    #endif
                    throw RakutenError.http(http.statusCode, detail)
                }
            }
            let decoded = try JSONDecoder().decode(RakutenSearchResponse.self, from: data)
            return decoded.items.compactMap(\.toParsedBook)
        } catch let e as RakutenError {
            throw e
        } catch let e as DecodingError {
            throw RakutenError.decoding(e)
        } catch {
            throw RakutenError.network(error)
        }
    }
}
