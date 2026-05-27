import XCTest
@testable import MangaMarker

/// 任意のステータス/ボディを返す URLProtocol スタブ。
final class URLProtocolStub: URLProtocol {
    static var handler: ((URLRequest) -> (status: Int, body: Data))?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let handler = URLProtocolStub.handler, let url = request.url else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }
        let (status, body) = handler(request)
        let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

final class GoogleBooksServiceTests: XCTestCase {
    private func makeService() -> GoogleBooksService {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [URLProtocolStub.self]
        return GoogleBooksService(session: URLSession(configuration: config), apiKey: nil)
    }

    override func tearDown() {
        URLProtocolStub.handler = nil
        super.tearDown()
    }

    func test_searchByTitle_parses200() async throws {
        let json = """
        { "items": [ { "id": "x", "volumeInfo": {
            "title": "鬼滅の刃 1", "authors": ["吾峠呼世晴"], "publisher": "集英社",
            "publishedDate": "2016-06-03",
            "industryIdentifiers": [ {"type": "ISBN_13", "identifier": "9784088806556"} ]
        } } ] }
        """.data(using: .utf8)!
        URLProtocolStub.handler = { _ in (200, json) }

        let books = try await makeService().searchByTitle("鬼滅の刃")
        XCTAssertEqual(books.count, 1)
        XCTAssertEqual(books.first?.isbn, "9784088806556")
        XCTAssertEqual(books.first?.volumeNumber, 1)
    }

    func test_searchByTitle_emptyReturnsEmpty() async throws {
        URLProtocolStub.handler = { _ in (200, #"{ "items": [] }"#.data(using: .utf8)!) }
        let books = try await makeService().searchByTitle("存在しない作品")
        XCTAssertTrue(books.isEmpty)
    }

    func test_request_429MapsToRateLimited() async {
        URLProtocolStub.handler = { _ in (429, Data()) }
        do {
            _ = try await makeService().searchByTitle("any")
            XCTFail("rateLimited が throw されるべき")
        } catch let error as GoogleBooksError {
            guard case .rateLimited = error else { return XCTFail("想定外: \(error)") }
        } catch {
            XCTFail("想定外の型: \(error)")
        }
    }

    func test_request_500MapsToHTTPError() async {
        URLProtocolStub.handler = { _ in (500, #"{"error":"boom"}"#.data(using: .utf8)!) }
        do {
            _ = try await makeService().searchByTitle("any")
            XCTFail("http エラーが throw されるべき")
        } catch let error as GoogleBooksError {
            guard case .http(let code, _) = error else { return XCTFail("想定外: \(error)") }
            XCTAssertEqual(code, 500)
        } catch {
            XCTFail("想定外の型: \(error)")
        }
    }
}
