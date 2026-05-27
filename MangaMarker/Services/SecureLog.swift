import Foundation

/// 機微情報を含みうる文字列をログ出力する際のマスキングユーティリティ。
enum SecureLog {
    /// URL のクエリから API キー等の秘匿パラメータを伏字にした文字列を返す。
    /// 例: `...?key=AIza...&q=foo` → `...?key=***&q=foo`
    static func redactedURL(_ url: URL) -> String {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return url.path
        }
        let secretParams: Set<String> = ["key", "accessKey", "applicationId"]
        components.queryItems = components.queryItems?.map { item in
            secretParams.contains(item.name) ? URLQueryItem(name: item.name, value: "***") : item
        }
        return components.url?.absoluteString ?? url.path
    }
}
