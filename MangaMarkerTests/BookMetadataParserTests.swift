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

    func test_extractVolumeNumber_fullwidth() {
        // 楽天Kobo は全角数字・全角括弧を使うことが多い
        XCTAssertEqual(BookMetadataParser.extractVolumeNumber(from: "あくたの死に際（４）"), 4)
        XCTAssertEqual(BookMetadataParser.extractVolumeNumber(from: "獣王と薬草（８）"), 8)
        XCTAssertEqual(BookMetadataParser.extractVolumeNumber(from: "鬼滅の刃　第１２巻"), 12)
    }

    func test_normalizeWidth_keepsJapanese() {
        // カタカナ・漢字・ひらがなは変換しない、ASCII 全角のみ半角化
        XCTAssertEqual(BookMetadataParser.normalizeWidth("あくたの死に際（４）"), "あくたの死に際(4)")
        XCTAssertEqual(BookMetadataParser.normalizeWidth("ナルト"), "ナルト")
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

    func test_stripVolumeSuffix() {
        XCTAssertEqual(BookMetadataParser.stripVolumeSuffix(from: "鬼滅の刃 23"), "鬼滅の刃")
        XCTAssertEqual(BookMetadataParser.stripVolumeSuffix(from: "鬼滅の刃 第23巻"), "鬼滅の刃")
        XCTAssertEqual(BookMetadataParser.stripVolumeSuffix(from: "Berserk vol.40"), "Berserk")
        XCTAssertEqual(BookMetadataParser.stripVolumeSuffix(from: "サンプル (12)"), "サンプル")
        // 全角括弧・全角数字の巻数も除去
        XCTAssertEqual(BookMetadataParser.stripVolumeSuffix(from: "あくたの死に際（４）"), "あくたの死に際")
        // タイトル先頭の数字や巻数の無いタイトルは保持
        XCTAssertEqual(BookMetadataParser.stripVolumeSuffix(from: "20世紀少年 3"), "20世紀少年")
        XCTAssertEqual(BookMetadataParser.stripVolumeSuffix(from: "AKIRA"), "AKIRA")
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

    func test_decodingWrappedV1Structure() throws {
        // formatVersion 未指定の v1 レスポンス: Items が {"Item": {...}} の配列
        let json = """
        {
          "Items": [
            {
              "Item": {
                "title": "ワンピース 100",
                "seriesName": "ONE PIECE",
                "author": "尾田栄一郎",
                "itemNumber": "kobo-99999",
                "salesDate": "2021年09月03日"
              }
            }
          ],
          "count": 1
        }
        """.data(using: .utf8)!

        let response = try JSONDecoder().decode(RakutenKoboResponse.self, from: json)
        let parsed = response.items.compactMap(\.toParsedBook)
        XCTAssertEqual(parsed.count, 1)
        XCTAssertEqual(parsed.first?.isbn, "kobo-99999")
        XCTAssertEqual(parsed.first?.volumeNumber, 100)
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
        func searchAllVolumes(seriesName: String) async throws -> [OpenBDParsedBook] {
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

final class SeriesVolumeFilterTests: XCTestCase {
    private func book(_ title: String, series: String?, volume: Int?, isbn: String? = nil) -> OpenBDParsedBook {
        OpenBDParsedBook(isbn: isbn, title: title, series: series, volumeNumber: volume,
                         author: "", publisher: nil, coverImageURL: nil, publishedAt: nil)
    }

    func test_representatives_oneRepresentativePerSeries_lowestVolume() {
        let input = [
            book("鬼滅の刃 23", series: "鬼滅の刃", volume: 23),
            book("鬼滅の刃 1", series: "鬼滅の刃", volume: 1),
            book("ONE PIECE 100", series: "ONE PIECE", volume: 100)
        ]
        let reps = SeriesVolumeFilter.representatives(from: input)
        XCTAssertEqual(reps.count, 2)
        // 鬼滅は最小巻 (1巻) が代表
        XCTAssertEqual(reps.first?.volumeNumber, 1)
        XCTAssertEqual(reps.first?.series, "鬼滅の刃")
    }

    func test_representatives_groupsBySeriesEvenWhenSeriesFieldNil() {
        // series が nil でもタイトルから巻数を除いて集約できること (代表のみ登録バグの回帰)
        let input = [
            book("鬼滅の刃 3", series: nil, volume: 3),
            book("鬼滅の刃 1", series: nil, volume: 1),
            book("鬼滅の刃 2", series: nil, volume: 2)
        ]
        let reps = SeriesVolumeFilter.representatives(from: input)
        XCTAssertEqual(reps.count, 1)
        XCTAssertEqual(reps.first?.volumeNumber, 1)
    }

    func test_allVolumes_matchesWhenSeriesFieldNil() {
        // searchAllVolumes 相当: series が nil の巻でもクリーンなシリーズ名で照合できること
        let input = [
            book("鬼滅の刃 1", series: nil, volume: 1),
            book("鬼滅の刃 2", series: nil, volume: 2),
            book("鬼滅の刃 3", series: nil, volume: 3)
        ]
        let volumes = SeriesVolumeFilter.allVolumes(from: input, seriesName: "鬼滅の刃")
        XCTAssertEqual(volumes.map(\.volumeNumber), [1, 2, 3])
    }

    func test_allVolumes_recoversUnnumberedFirstVolume() {
        // 1 巻がタイトルに巻数を持たない作品 (例: "ワンナイト・モーニング" = 1巻) を補完できること
        let input = [
            book("ワンナイト・モーニング", series: nil, volume: nil),
            book("ワンナイト・モーニング 2", series: nil, volume: 2),
            book("ワンナイト・モーニング 3", series: nil, volume: 3)
        ]
        let volumes = SeriesVolumeFilter.allVolumes(from: input, seriesName: "ワンナイト・モーニング")
        XCTAssertEqual(volumes.map(\.volumeNumber), [1, 2, 3])
    }

    func test_allVolumes_dropsUnnumberedGuidebook() {
        // 余分な語が付く無番号本 (ガイドブック等) は 1 巻補完の対象外
        let input = [
            book("ワンナイト・モーニング 公式ガイド", series: nil, volume: nil),
            book("ワンナイト・モーニング 1", series: nil, volume: 1),
            book("ワンナイト・モーニング 2", series: nil, volume: 2)
        ]
        let volumes = SeriesVolumeFilter.allVolumes(from: input, seriesName: "ワンナイト・モーニング")
        XCTAssertEqual(volumes.map(\.volumeNumber), [1, 2])
    }

    func test_allVolumes_dedupByVolumeNumber_preferISBN_sortedAscending() {
        let input = [
            book("鬼滅の刃 2", series: "鬼滅の刃", volume: 2, isbn: nil),
            book("鬼滅の刃 2 (廉価版)", series: "鬼滅の刃", volume: 2, isbn: "9784000000022"),
            book("鬼滅の刃 1", series: "鬼滅の刃", volume: 1, isbn: "9784000000011"),
            book("無関係作品 1", series: "別の漫画", volume: 1)
        ]
        let volumes = SeriesVolumeFilter.allVolumes(from: input, seriesName: "鬼滅の刃")
        XCTAssertEqual(volumes.map(\.volumeNumber), [1, 2])
        // 2巻は ISBN 持ちが優先される
        XCTAssertEqual(volumes.last?.isbn, "9784000000022")
    }
}
