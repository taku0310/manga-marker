import Foundation

enum OpenBDError: LocalizedError {
    case invalidURL
    case notFound
    case network(Error)
    case decoding(Error)

    var errorDescription: String? {
        switch self {
        case .invalidURL: return "URLが不正です"
        case .notFound: return "書籍が見つかりませんでした"
        case .network(let e): return "通信エラー: \(e.localizedDescription)"
        case .decoding(let e): return "データ解析エラー: \(e.localizedDescription)"
        }
    }
}

final class OpenBDService: @unchecked Sendable {
    private let session: URLSession
    private let baseURL = URL(string: "https://api.openbd.jp/v1")!

    init(session: URLSession = .shared) {
        self.session = session
    }

    /// 単一ISBNでの取得
    func fetch(isbn: String) async throws -> OpenBDParsedBook {
        let books = try await fetch(isbns: [isbn])
        guard let book = books.first else { throw OpenBDError.notFound }
        return book
    }

    /// 複数ISBNを一括取得（OpenBDは1回のリクエストで最大10000件まで対応）
    func fetch(isbns: [String]) async throws -> [OpenBDParsedBook] {
        guard !isbns.isEmpty else { return [] }
        let joined = isbns.joined(separator: ",")
        guard var components = URLComponents(url: baseURL.appendingPathComponent("get"), resolvingAgainstBaseURL: false) else {
            throw OpenBDError.invalidURL
        }
        components.queryItems = [URLQueryItem(name: "isbn", value: joined)]
        guard let url = components.url else { throw OpenBDError.invalidURL }

        do {
            let (data, response) = try await session.data(from: url)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                throw OpenBDError.notFound
            }
            let decoder = JSONDecoder()
            let raw = try decoder.decode([OpenBDBook?].self, from: data)
            return raw.compactMap { $0 }.compactMap(parse(book:))
        } catch let e as OpenBDError {
            throw e
        } catch let e as DecodingError {
            throw OpenBDError.decoding(e)
        } catch {
            throw OpenBDError.network(error)
        }
    }

    // MARK: - Parsing

    private func parse(book: OpenBDBook) -> OpenBDParsedBook? {
        guard let summary = book.summary, let isbn = summary.isbn, let title = summary.title else {
            return nil
        }
        let series = summary.series?.isEmpty == false ? summary.series : nil
        let publisher = summary.publisher?.isEmpty == false ? summary.publisher : nil
        let author = summary.author ?? ""
        let cover = summary.cover?.isEmpty == false ? summary.cover : nil
        let publishedAt = BookMetadataParser.parseOpenBDDate(summary.pubdate)
        let volume = BookMetadataParser.extractVolumeNumber(from: summary.volume)
            ?? BookMetadataParser.extractVolumeNumber(from: title)

        return OpenBDParsedBook(
            isbn: isbn,
            title: title,
            series: series,
            volumeNumber: volume,
            author: author,
            publisher: publisher,
            coverImageURL: cover,
            publishedAt: publishedAt
        )
    }

}
