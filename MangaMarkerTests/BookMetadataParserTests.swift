import XCTest
@testable import MangaMarker

final class BookMetadataParserTests: XCTestCase {
    func test_extractVolumeNumber_japanese() {
        XCTAssertEqual(BookMetadataParser.extractVolumeNumber(from: "鬼滅の刃 第3巻"), 3)
        XCTAssertEqual(BookMetadataParser.extractVolumeNumber(from: "ワンピース 99巻"), 99)
    }

    func test_extractVolumeNumber_volPrefix() {
        XCTAssertEqual(BookMetadataParser.extractVolumeNumber(from: "Berserk vol.40"), 40)
        XCTAssertEqual(BookMetadataParser.extractVolumeNumber(from: "VOL. 7"), 7)
    }

    func test_extractVolumeNumber_parenthesis() {
        XCTAssertEqual(BookMetadataParser.extractVolumeNumber(from: "サンプルタイトル (12)"), 12)
    }

    func test_extractVolumeNumber_nil() {
        XCTAssertNil(BookMetadataParser.extractVolumeNumber(from: nil))
        XCTAssertNil(BookMetadataParser.extractVolumeNumber(from: "巻数情報なし"))
    }

    func test_parseGoogleBooksDate() {
        XCTAssertNotNil(BookMetadataParser.parseGoogleBooksDate("2024-01-04"))
        XCTAssertNotNil(BookMetadataParser.parseGoogleBooksDate("2024-01"))
        XCTAssertNotNil(BookMetadataParser.parseGoogleBooksDate("2024"))
        XCTAssertNil(BookMetadataParser.parseGoogleBooksDate(nil))
    }

    func test_parseOpenBDDate_compact() {
        XCTAssertNotNil(BookMetadataParser.parseOpenBDDate("20240104"))
        XCTAssertNotNil(BookMetadataParser.parseOpenBDDate("2024-01-04"))
    }

    func test_normalizeTitle() {
        XCTAssertEqual(BookMetadataParser.normalizeTitle("ONE PIECE"), "onepiece")
        XCTAssertEqual(BookMetadataParser.normalizeTitle("鬼滅 の 刃"), "鬼滅の刃")
    }
}

final class GoogleBookDecodingTests: XCTestCase {
    func test_decodingAndMapping() throws {
        let json = #"""
        {
          "items": [
            {
              "id": "abc",
              "volumeInfo": {
                "title": "鬼滅の刃 23",
                "authors": ["吾峠呼世晴"],
                "publisher": "集英社",
                "publishedDate": "2020-12-04",
                "industryIdentifiers": [
                  {"type": "ISBN_10", "identifier": "4088832434"},
                  {"type": "ISBN_13", "identifier": "9784088832432"}
                ],
                "imageLinks": {
                  "thumbnail": "http://books.google.com/books/content?id=abc&printsec=frontcover&img=1&zoom=1"
                },
                "language": "ja"
              }
            }
          ]
        }
        """#.data(using: .utf8)!

        let response = try JSONDecoder().decode(GoogleBooksResponse.self, from: json)
        let parsed = (response.items ?? []).compactMap(\.toParsedBook)
        XCTAssertEqual(parsed.count, 1)
        let book = try XCTUnwrap(parsed.first)
        XCTAssertEqual(book.isbn, "9784088832432")
        XCTAssertEqual(book.series, "鬼滅の刃")
        XCTAssertEqual(book.volumeNumber, 23)
        XCTAssertTrue(book.coverImageURL?.hasPrefix("https://") ?? false)
        XCTAssertNotNil(book.publishedAt)
    }

    func test_rejectsItemMissingISBN() throws {
        let json = #"""
        {
          "items": [
            { "id": "noisbn", "volumeInfo": { "title": "no-isbn" } }
          ]
        }
        """#.data(using: .utf8)!
        let response = try JSONDecoder().decode(GoogleBooksResponse.self, from: json)
        XCTAssertTrue((response.items ?? []).compactMap(\.toParsedBook).isEmpty)
    }
}

final class RakutenKoboDecodingTests: XCTestCase {
    func test_decodingAndMapping_withoutISBN() throws {
        let json = """
        {
          "Items": [
            {
              "title": "鬼滅の刃 23",
              "seriesName": "鬼滅の刃",
              "author": "吾峠呼世晴",
              "publisherName": "集英社",
              "itemNumber": "kobo-12345",
              "salesDate": "2020年12月04日",
              "largeImageUrl": "http://thumbnail.image.rakuten.co.jp/cover.jpg"
            }
          ],
          "count": 1
        }
        """.data(using: .utf8)!

        let response = try JSONDecoder().decode(RakutenKoboResponse.self, from: json)
        let parsed = response.items.compactMap(\.toParsedBook)
        XCTAssertEqual(parsed.count, 1)
        let book = try XCTUnwrap(parsed.first)
        // ISBN が無いため itemNumber が識別子に使われる
        XCTAssertEqual(book.isbn, "kobo-12345")
        XCTAssertEqual(book.series, "鬼滅の刃")
        XCTAssertEqual(book.volumeNumber, 23)
        XCTAssertTrue(book.coverImageURL?.hasPrefix("https://") ?? false)
        XCTAssertNotNil(book.publishedAt)
    }

    func test_rejectsItemMissingTitle() throws {
        let json = """
        { "Items": [ { "author": "x" } ] }
        """.data(using: .utf8)!
        let response = try JSONDecoder().decode(RakutenKoboResponse.self, from: json)
        XCTAssertTrue(response.items.compactMap(\.toParsedBook).isEmpty)
    }
}

final class CompositeBookSearchServiceTests: XCTestCase {
    private final class StubService: BookSearchService {
        let result: [OpenBDParsedBook]
        let error: Error?
        var titleCallCount = 0
        init(result: [OpenBDParsedBook] = [], error: Error? = nil) {
            self.result = result
            self.error = error
        }
        func searchByTitle(_ title: String, maxResults: Int) async throws -> [OpenBDParsedBook] {
            titleCallCount += 1
            if let error { throw error }
            return result
        }
        func searchSeries(_ seriesName: String, maxResults: Int) async throws -> [OpenBDParsedBook] {
            if let error { throw error }
            return result
        }
    }

    private func sampleBook(_ title: String) -> OpenBDParsedBook {
        OpenBDParsedBook(isbn: nil, title: title, series: nil, volumeNumber: 1,
                         author: "", publisher: nil, coverImageURL: nil, publishedAt: nil)
    }

    func test_usesPrimaryWhenPrimaryReturnsResults() async throws {
        let primary = StubService(result: [sampleBook("primary")])
        let fallback = StubService(result: [sampleBook("fallback")])
        let composite = CompositeBookSearchService(primary: primary, fallback: fallback)
        let results = try await composite.searchByTitle("鬼滅", maxResults: 30)
        XCTAssertEqual(results.first?.title, "primary")
        XCTAssertEqual(fallback.titleCallCount, 0)
    }

    func test_fallsBackWhenPrimaryEmpty() async throws {
        let primary = StubService(result: [])
        let fallback = StubService(result: [sampleBook("fallback")])
        let composite = CompositeBookSearchService(primary: primary, fallback: fallback)
        let results = try await composite.searchByTitle("鬼滅", maxResults: 30)
        XCTAssertEqual(results.first?.title, "fallback")
    }

    func test_fallsBackWhenPrimaryThrows() async throws {
        struct Boom: Error {}
        let primary = StubService(error: Boom())
        let fallback = StubService(result: [sampleBook("fallback")])
        let composite = CompositeBookSearchService(primary: primary, fallback: fallback)
        let results = try await composite.searchByTitle("鬼滅", maxResults: 30)
        XCTAssertEqual(results.first?.title, "fallback")
    }
}
