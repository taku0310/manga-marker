import Foundation

/// 書誌 API のテキスト/日付を正規化するための共有パーサ。
enum BookMetadataParser {
    /// 「第3巻」「vol.5」「(12)」「巻末の単独数字」などから巻数を抽出する。
    static func extractVolumeNumber(from text: String?) -> Int? {
        guard let text else { return nil }
        let patterns = [
            "(?:第)?(\\d+)\\s*巻",
            "vol\\.?\\s*(\\d+)",
            "\\((\\d+)\\)",
            "\\b(\\d+)\\b"
        ]
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { continue }
            if let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
               match.numberOfRanges > 1,
               let range = Range(match.range(at: 1), in: text),
               let n = Int(text[range]) {
                return n
            }
        }
        return nil
    }

    /// OpenBD の `pubdate` 形式 (yyyyMMdd 等) を Date に変換。
    static func parseOpenBDDate(_ raw: String?) -> Date? {
        guard let raw, !raw.isEmpty else { return nil }
        return parse(raw, formats: ["yyyyMMdd", "yyyy-MM-dd", "yyyy/MM/dd"], locale: "en_US_POSIX")
    }

    /// Google Books の `publishedDate` (例: "2024-01-04", "2024-01", "2024") を Date に変換。
    static func parseGoogleBooksDate(_ raw: String?) -> Date? {
        guard let raw, !raw.isEmpty else { return nil }
        return parse(raw, formats: ["yyyy-MM-dd", "yyyy-MM", "yyyy"], locale: "en_US_POSIX")
    }

    /// シリーズ名の同一性比較用に文字列を正規化 (全角/半角空白除去・小文字化)。
    static func normalizeTitle(_ s: String) -> String {
        s.lowercased()
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "　", with: "")
            .replacingOccurrences(of: "・", with: "")
    }

    private static func parse(_ raw: String, formats: [String], locale: String) -> Date? {
        for fmt in formats {
            let f = DateFormatter()
            f.locale = Locale(identifier: locale)
            f.timeZone = TimeZone(identifier: "Asia/Tokyo")
            f.dateFormat = fmt
            if let d = f.date(from: raw) { return d }
        }
        return nil
    }
}
