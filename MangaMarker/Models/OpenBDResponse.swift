import Foundation

struct OpenBDBook: Decodable {
    let summary: Summary?
    let onix: Onix?

    struct Summary: Decodable {
        let isbn: String?
        let title: String?
        let volume: String?
        let series: String?
        let publisher: String?
        let pubdate: String?
        let cover: String?
        let author: String?
    }

    struct Onix: Decodable {
        let descriptiveDetail: DescriptiveDetail?
        let publishingDetail: PublishingDetail?

        enum CodingKeys: String, CodingKey {
            case descriptiveDetail = "DescriptiveDetail"
            case publishingDetail = "PublishingDetail"
        }
    }

    struct DescriptiveDetail: Decodable {
        let titleDetail: TitleDetail?
        let collection: Collection?

        enum CodingKeys: String, CodingKey {
            case titleDetail = "TitleDetail"
            case collection = "Collection"
        }
    }

    struct TitleDetail: Decodable {
        let titleElement: TitleElement?

        enum CodingKeys: String, CodingKey {
            case titleElement = "TitleElement"
        }
    }

    struct TitleElement: Decodable {
        let titleText: TitleText?
        let partNumber: String?

        enum CodingKeys: String, CodingKey {
            case titleText = "TitleText"
            case partNumber = "PartNumber"
        }
    }

    struct TitleText: Decodable {
        let content: String?
    }

    struct Collection: Decodable {
        let titleDetail: TitleDetail?

        enum CodingKeys: String, CodingKey {
            case titleDetail = "TitleDetail"
        }
    }

    struct PublishingDetail: Decodable {
        let publishingDate: [PublishingDate]?

        enum CodingKeys: String, CodingKey {
            case publishingDate = "PublishingDate"
        }
    }

    struct PublishingDate: Decodable {
        let date: String?

        enum CodingKeys: String, CodingKey {
            case date = "Date"
        }
    }
}

struct OpenBDParsedBook: Hashable, Identifiable {
    /// ISBN または書誌固有 ID。楽天Kobo の電子書籍など ISBN を持たないソースでは nil になりうる。
    let isbn: String?
    let title: String
    let series: String?
    let volumeNumber: Int?
    let author: String
    let publisher: String?
    let coverImageURL: String?
    let publishedAt: Date?

    /// SwiftUI の List / 重複排除用の安定キー。ISBN が無い場合はタイトル+著者+巻数で代替する。
    var id: String {
        if let isbn, !isbn.isEmpty { return isbn }
        return "\(title)|\(author)|\(volumeNumber.map(String.init) ?? "")"
    }

    /// シリーズ名。`series` があればそれを、無ければタイトルから巻数表記を除いたものを返す。
    /// 全巻取得・シリーズ集約のキーとして用いる (巻数つきタイトルの混入を防ぐ)。
    var seriesTitle: String {
        if let series, !series.isEmpty { return series }
        return BookMetadataParser.stripVolumeSuffix(from: title)
    }

    /// 巻数を補完したコピーを返す (タイトルに巻数が無い 1 巻などの補正用)。
    func withVolumeNumber(_ number: Int) -> OpenBDParsedBook {
        OpenBDParsedBook(
            isbn: isbn,
            title: title,
            series: series,
            volumeNumber: number,
            author: author,
            publisher: publisher,
            coverImageURL: coverImageURL,
            publishedAt: publishedAt
        )
    }
}
