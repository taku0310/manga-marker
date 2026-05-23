import Foundation

enum GoogleBooksError: LocalizedError {
    case invalidURL
    case notFound
    case rateLimited(usingApiKey: Bool)
    case http(Int, String?)
    case network(Error)
    case decoding(Error)

    var errorDescription: String? {
        switch self {
        case .invalidURL: return "URLが不正です"
        case .notFound: return "該当する書籍が見つかりませんでした"
        case .rateLimited(let usingApiKey):
            if usingApiKey {
                return "アクセス制限に達しました (API キー使用中)。クォータを確認するか、しばらく待ってから再試行してください。"
            }
            return "Google Books API のアクセス制限に達しました。匿名利用は IP ベースで強く制限されます。Info.plist の GoogleBooksApiKey に Google Cloud Console で発行した API キーを設定してください (無料・100,000 req/日)。"
        case .http(let code, let detail):
            if let detail, !detail.isEmpty { return "HTTPエラー \(code): \(detail)" }
            return "HTTPエラー: \(code)"
        case .network(let e): return "通信エラー: \(e.localizedDescription)"
        case .decoding(let e): return "データ解析エラー: \(e.localizedDescription)"
        }
    }
}

/// Google Books API クライアント。
///
/// - 認証不要 (匿名で 1,000 req/日まで使える)。
/// - `AppConfig.googleBooksApiKey` が設定されていれば `key=` クエリで送付しクォータを拡大できる。
/// - 日本語マンガ用途のため `langRestrict=ja` `printType=books` を既定で付与。
/// - ISBN を含まない結果は `GoogleBook.toParsedBook` で除外される (DB 整合性のため)。
///
/// https://developers.google.com/books/docs/v1/using
final class GoogleBooksService {
    private let session: URLSession
    private let baseURL = URL(string: "https://www.googleapis.com/books/v1/volumes")!
    private let apiKey: String?

    init(session: URLSession = .shared, apiKey: String? = AppConfig.googleBooksApiKey) {
        self.session = session
        self.apiKey = apiKey
    }

    /// タイトル/シリーズ名でのフリーテキスト検索。`intitle:` を付けてタイトル優先で検索する。
    /// 並び順はクライアント側で発売日降順。
    func searchByTitle(_ title: String, maxResults: Int = 30) async throws -> [OpenBDParsedBook] {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        let books = try await request(query: "intitle:\(trimmed)", maxResults: maxResults)
        return books.sorted { ($0.publishedAt ?? .distantPast) > ($1.publishedAt ?? .distantPast) }
    }

    /// シリーズ名から新刊候補を取得する。NewReleaseChecker 用。
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

    // MARK: - Private

    private func request(query: String, maxResults: Int) async throws -> [OpenBDParsedBook] {
        guard var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else {
            throw GoogleBooksError.invalidURL
        }
        var items: [URLQueryItem] = [
            URLQueryItem(name: "q", value: query),
            URLQueryItem(name: "maxResults", value: String(min(max(maxResults, 1), 40))),
            URLQueryItem(name: "langRestrict", value: "ja"),
            URLQueryItem(name: "printType", value: "books"),
            URLQueryItem(name: "orderBy", value: "relevance")
        ]
        if let apiKey, !apiKey.isEmpty {
            items.append(URLQueryItem(name: "key", value: apiKey))
        }
        components.queryItems = items
        guard let url = components.url else { throw GoogleBooksError.invalidURL }

        var urlRequest = URLRequest(url: url)
        // iOS アプリ制限つき API キーを使う場合、Google API は
        // X-Ios-Bundle-Identifier ヘッダで Bundle ID を判定する。
        // 未送信だと API_KEY_IOS_APP_BLOCKED (iosBundleId=<empty>) で 403 が返るため必ず付与。
        if let bundleId = Bundle.main.bundleIdentifier {
            urlRequest.setValue(bundleId, forHTTPHeaderField: "X-Ios-Bundle-Identifier")
        }

        #if DEBUG
        print("[GoogleBooks] GET \(url.absoluteString)")
        if let bundleId = urlRequest.value(forHTTPHeaderField: "X-Ios-Bundle-Identifier") {
            print("[GoogleBooks] X-Ios-Bundle-Identifier: \(bundleId)")
        }
        #endif

        do {
            let (data, response) = try await session.data(for: urlRequest)
            if let http = response as? HTTPURLResponse {
                let body = String(data: data, encoding: .utf8)
                switch http.statusCode {
                case 200..<300:
                    break
                case 429:
                    #if DEBUG
                    print("[GoogleBooks] HTTP 429 body: \(body ?? "")")
                    #endif
                    throw GoogleBooksError.rateLimited(usingApiKey: apiKey?.isEmpty == false)
                case 403:
                    // Google APIs はクォータ超過時に 403 + rateLimitExceeded で返すことがある
                    #if DEBUG
                    print("[GoogleBooks] HTTP 403 body: \(body ?? "")")
                    #endif
                    if (body ?? "").localizedCaseInsensitiveContains("rateLimitExceeded")
                        || (body ?? "").localizedCaseInsensitiveContains("Daily Limit") {
                        throw GoogleBooksError.rateLimited(usingApiKey: apiKey?.isEmpty == false)
                    }
                    throw GoogleBooksError.http(http.statusCode, body)
                case 404:
                    throw GoogleBooksError.notFound
                default:
                    #if DEBUG
                    print("[GoogleBooks] HTTP \(http.statusCode) body: \(body ?? "")")
                    #endif
                    throw GoogleBooksError.http(http.statusCode, body)
                }
            }
            let decoded = try JSONDecoder().decode(GoogleBooksResponse.self, from: data)
            return (decoded.items ?? []).compactMap(\.toParsedBook)
        } catch let e as GoogleBooksError {
            throw e
        } catch let e as DecodingError {
            throw GoogleBooksError.decoding(e)
        } catch {
            throw GoogleBooksError.network(error)
        }
    }
}
