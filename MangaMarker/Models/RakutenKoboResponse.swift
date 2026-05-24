import Foundation

/// 楽天Kobo電子書籍検索API のレスポンス。
/// formatVersion 未指定 (v1) では `Items` が `[{"Item": {...}}]`、
/// formatVersion=2 では `Items` が `[{...}]` のフラット配列になるため、両方に対応する。
/// https://webservice.rakuten.co.jp/documentation/kobo-ebook-search
struct RakutenKoboResponse: Decodable {
    let items: [RakutenKoboItem]

    enum CodingKeys: String, CodingKey {
        case items = "Items"
    }

    private struct ItemWrapper: Decodable {
        let item: RakutenKoboItem
        enum CodingKeys: String, CodingKey { case item = "Item" }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        // v1 (wrapped) を優先的に試す。フラット構造では "Item" キーが無く失敗するため、その場合は v2 として解釈。
        if let wrapped = try? container.decode([ItemWrapper].self, forKey: .items) {
            items = wrapped.map(\.item)
        } else {
            items = (try? container.decode([RakutenKoboItem].self, forKey: .items)) ?? []
        }
    }
}

struct RakutenKoboItem: Decodable {
    let title: String?
    let subTitle: String?
    let seriesName: String?
    let author: String?
    let publisherName: String?
    let itemNumber: String?
    let isbn: String?
    let salesDate: String?
    let imageUrl: String?
    let largeImageUrl: String?

    var toParsedBook: OpenBDParsedBook? {
        guard let rawTitle = title, !rawTitle.isEmpty else { return nil }

        let fullTitle: String = {
            if let sub = subTitle, !sub.isEmpty { return "\(rawTitle) \(sub)" }
            return rawTitle
        }()
        let series = (seriesName?.isEmpty == false) ? seriesName : nil
        let publisher = (publisherName?.isEmpty == false) ? publisherName : nil
        // Kobo 電子書籍は ISBN を持たないことが多いので、無ければ itemNumber を識別子に使う。
        let identifier: String? = {
            if let isbn, !isbn.isEmpty { return isbn }
            if let itemNumber, !itemNumber.isEmpty { return itemNumber }
            return nil
        }()
        let rawCover = (largeImageUrl?.isEmpty == false) ? largeImageUrl : imageUrl
        let cover = rawCover?.replacingOccurrences(of: "http://", with: "https://")
        let volumeNumber = BookMetadataParser.extractVolumeNumber(from: fullTitle)
            ?? BookMetadataParser.extractVolumeNumber(from: seriesName)

        return OpenBDParsedBook(
            isbn: identifier,
            title: fullTitle,
            series: series,
            volumeNumber: volumeNumber,
            author: author ?? "",
            publisher: publisher,
            coverImageURL: cover,
            publishedAt: BookMetadataParser.parseRakutenSalesDate(salesDate)
        )
    }
}
