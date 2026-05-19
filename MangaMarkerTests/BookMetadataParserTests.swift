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

    func test_parseRakutenSalesDate_full() {
        XCTAssertNotNil(BookMetadataParser.parseRakutenSalesDate("2024年01月04日"))
    }

    func test_parseRakutenSalesDate_partial() {
        XCTAssertNotNil(BookMetadataParser.parseRakutenSalesDate("2024年01月"))
        XCTAssertNotNil(BookMetadataParser.parseRakutenSalesDate("2024年"))
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

final class RakutenItemDecodingTests: XCTestCase {
    func test_decodingAndMapping() throws {
        let json = """
        {
          "Items": [
            {
              "title": "鬼滅の刃 23",
              "author": "吾峠呼世晴",
              "publisherName": "集英社",
              "seriesName": "鬼滅の刃",
              "isbn": "9784088832432",
              "largeImageUrl": "http://example.com/cover.jpg",
              "salesDate": "2020年12月04日"
            }
          ]
        }
        """.data(using: .utf8)!

        let response = try JSONDecoder().decode(RakutenSearchResponse.self, from: json)
        let parsed = response.items.compactMap(\.toParsedBook)
        XCTAssertEqual(parsed.count, 1)
        let book = try XCTUnwrap(parsed.first)
        XCTAssertEqual(book.isbn, "9784088832432")
        XCTAssertEqual(book.series, "鬼滅の刃")
        XCTAssertEqual(book.volumeNumber, 23)
        XCTAssertEqual(book.coverImageURL, "https://example.com/cover.jpg")
        XCTAssertNotNil(book.publishedAt)
    }

    func test_rejectsItemMissingISBN() throws {
        let json = """
        {
          "Items": [
            { "title": "no-isbn", "author": "x" }
          ]
        }
        """.data(using: .utf8)!
        let response = try JSONDecoder().decode(RakutenSearchResponse.self, from: json)
        XCTAssertTrue(response.items.compactMap(\.toParsedBook).isEmpty)
    }
}
