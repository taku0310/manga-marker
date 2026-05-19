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
    var id: String { isbn }
    let isbn: String
    let title: String
    let series: String?
    let volumeNumber: Int?
    let author: String
    let publisher: String?
    let coverImageURL: String?
    let publishedAt: Date?
}
