import Foundation

/// Google Books API レスポンス。
/// https://developers.google.com/books/docs/v1/reference/volumes
struct GoogleBooksResponse: Decodable {
    let items: [GoogleBook]?
    let totalItems: Int?
}

struct GoogleBook: Decodable {
    let id: String
    let volumeInfo: GoogleVolumeInfo
}

struct GoogleVolumeInfo: Decodable {
    let title: String?
    let subtitle: String?
    let authors: [String]?
    let publisher: String?
    let publishedDate: String?
    let industryIdentifiers: [IndustryIdentifier]?
    let imageLinks: ImageLinks?
    let language: String?
    let description: String?

    struct IndustryIdentifier: Decodable {
        let type: String
        let identifier: String
    }

    struct ImageLinks: Decodable {
        let smallThumbnail: String?
        let thumbnail: String?
    }

    var preferredISBN: String? {
        if let i13 = industryIdentifiers?.first(where: { $0.type == "ISBN_13" }) {
            return i13.identifier
        }
        return industryIdentifiers?.first(where: { $0.type == "ISBN_10" })?.identifier
    }
}

extension GoogleBook {
    /// 検索結果 1 件を共通モデルへ正規化。
    /// - ISBN が無いものは除外 (DB のキー整合性のため)。
    /// - サムネイル URL は https に矯正。
    var toParsedBook: OpenBDParsedBook? {
        guard let rawTitle = volumeInfo.title, !rawTitle.isEmpty else { return nil }
        guard let isbn = volumeInfo.preferredISBN, !isbn.isEmpty else { return nil }

        let fullTitle: String = {
            if let sub = volumeInfo.subtitle, !sub.isEmpty {
                return "\(rawTitle) \(sub)"
            }
            return rawTitle
        }()
        let author = volumeInfo.authors?.joined(separator: ", ") ?? ""
        let publisher = (volumeInfo.publisher?.isEmpty == false) ? volumeInfo.publisher : nil
        let cover = (volumeInfo.imageLinks?.thumbnail ?? volumeInfo.imageLinks?.smallThumbnail)?
            .replacingOccurrences(of: "http://", with: "https://")
        let publishedAt = BookMetadataParser.parseGoogleBooksDate(volumeInfo.publishedDate)
        let volumeNumber = BookMetadataParser.extractVolumeNumber(from: fullTitle)
        let series = Self.inferSeriesName(from: fullTitle, volumeNumber: volumeNumber)

        return OpenBDParsedBook(
            isbn: isbn,
            title: fullTitle,
            series: series,
            volumeNumber: volumeNumber,
            author: author,
            publisher: publisher,
            coverImageURL: cover,
            publishedAt: publishedAt
        )
    }

    /// Google Books にはシリーズ名フィールドが無いため、タイトルから巻数表記を除いた残りをシリーズ名と推定。
    /// 例: "鬼滅の刃 23" → "鬼滅の刃"
    private static func inferSeriesName(from title: String, volumeNumber: Int?) -> String? {
        guard let volumeNumber else { return nil }
        let patterns = [
            "\\s*第?\\s*\(volumeNumber)\\s*巻\\s*$",
            "\\s*\\(\(volumeNumber)\\)\\s*$",
            "\\s+vol\\.?\\s*\(volumeNumber)\\s*$",
            "\\s+\(volumeNumber)\\s*$"
        ]
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { continue }
            let range = NSRange(title.startIndex..., in: title)
            let modified = regex.stringByReplacingMatches(in: title, range: range, withTemplate: "")
            if modified != title {
                let trimmed = modified.trimmingCharacters(in: .whitespaces)
                return trimmed.isEmpty ? nil : trimmed
            }
        }
        return nil
    }
}
