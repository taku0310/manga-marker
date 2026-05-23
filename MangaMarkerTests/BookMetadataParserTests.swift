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
