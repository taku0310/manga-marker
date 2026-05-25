import Foundation

/// 書誌 API のテキスト/日付を正規化するための共有パーサ。
enum BookMetadataParser {
    /// 全角の ASCII 相当文字 (数字・英字・記号・括弧) と全角スペースを半角へ変換する。
    /// カタカナ・ひらがな・漢字は変換しない。
    /// 例: "あくたの死に際（４）" → "あくたの死に際(4)"
    static func normalizeWidth(_ s: String) -> String {
        var scalars = String.UnicodeScalarView()
        for scalar in s.unicodeScalars {
            switch scalar.value {
            case 0xFF01...0xFF5E: // 全角 ASCII ブロック (！-～) → 半角 (!-~)
                scalars.append(UnicodeScalar(scalar.value - 0xFEE0)!)
            case 0x3000: // 全角スペース → 半角スペース
                scalars.append(UnicodeScalar(0x20)!)
            default:
                scalars.append(scalar)
            }
        }
        return String(scalars)
    }

    /// 「第3巻」「vol.5」「(12)」「巻末の単独数字」などから巻数を抽出する。全角数字にも対応。
    static func extractVolumeNumber(from text: String?) -> Int? {
        guard let text else { return nil }
        let normalized = normalizeWidth(text)
        let patterns = [
            "(?:第)?(\\d+)\\s*巻",
            "vol\\.?\\s*(\\d+)",
            "\\((\\d+)\\)",
            "\\b(\\d+)\\b"
        ]
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { continue }
            if let match = regex.firstMatch(in: normalized, range: NSRange(normalized.startIndex..., in: normalized)),
               match.numberOfRanges > 1,
               let range = Range(match.range(at: 1), in: normalized),
               let n = Int(normalized[range]) {
                return n
            }
        }
        return nil
    }

    /// タイトル末尾の巻数表記 (「 23」「第23巻」「(23)」「vol.23」「（４）」等) を除去してシリーズ名を得る。
    /// 例: "鬼滅の刃 23" → "鬼滅の刃" / "あくたの死に際（４）" → "あくたの死に際" / "AKIRA" → "AKIRA"
    static func stripVolumeSuffix(from title: String) -> String {
        let normalized = normalizeWidth(title)
        let patterns = [
            "\\s*第?\\s*\\d+\\s*巻\\s*$",
            "\\s*\\(\\d+\\)\\s*$",
            "\\s+vol\\.?\\s*\\d+\\s*$",
            "\\s+\\d+\\s*$"
        ]
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { continue }
            let range = NSRange(normalized.startIndex..., in: normalized)
            let stripped = regex.stringByReplacingMatches(in: normalized, range: range, withTemplate: "")
                .trimmingCharacters(in: .whitespaces)
            if stripped != normalized, !stripped.isEmpty {
                return stripped
            }
        }
        return normalized.trimmingCharacters(in: .whitespaces)
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

    /// 楽天 (Kobo / Books) の `salesDate` (例: "2024年01月04日") を Date に変換。
    static func parseRakutenSalesDate(_ raw: String?) -> Date? {
        guard let raw, !raw.isEmpty else { return nil }
        return parse(raw, formats: ["yyyy年MM月dd日", "yyyy年MM月", "yyyy年"], locale: "ja_JP_POSIX")
    }

    /// シリーズ名の同一性比較用に文字列を正規化 (全角→半角・空白除去・小文字化)。
    static func normalizeTitle(_ s: String) -> String {
        normalizeWidth(s).lowercased()
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
