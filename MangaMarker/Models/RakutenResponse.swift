import Foundation

/// 楽天ブックス書籍検索 API (formatVersion=2) のレスポンス。
struct RakutenSearchResponse: Decodable {
    let items: [RakutenItem]
    let count: Int?
    let page: Int?
    let pageCount: Int?

    enum CodingKeys: String, CodingKey {
        case items = "Items"
        case count, page, pageCount
    }
}

struct RakutenItem: Decodable {
    let title: String?
    let author: String?
    let publisherName: String?
    let seriesName: String?
    let isbn: String?
    let largeImageUrl: String?
    let mediumImageUrl: String?
    let smallImageUrl: String?
    let salesDate: String?
    let itemCaption: String?

    var toParsedBook: OpenBDParsedBook? {
        guard let isbn, !isbn.isEmpty, let title, !title.isEmpty else { return nil }
        let series = (seriesName?.isEmpty == false) ? seriesName : nil
        let publisher = (publisherName?.isEmpty == false) ? publisherName : nil
        let rawCover = (largeImageUrl?.isEmpty == false ? largeImageUrl
                        : (mediumImageUrl?.isEmpty == false ? mediumImageUrl : smallImageUrl))
        // 楽天 API は http で返してくる場合があるため https に統一
        let cover = rawCover?.replacingOccurrences(of: "http://", with: "https://")

        let volumeNumber = BookMetadataParser.extractVolumeNumber(from: title)
            ?? BookMetadataParser.extractVolumeNumber(from: seriesName)

        return OpenBDParsedBook(
            isbn: isbn,
            title: title,
            series: series,
            volumeNumber: volumeNumber,
            author: author ?? "",
            publisher: publisher,
            coverImageURL: cover,
            publishedAt: BookMetadataParser.parseRakutenSalesDate(salesDate)
        )
    }
}
