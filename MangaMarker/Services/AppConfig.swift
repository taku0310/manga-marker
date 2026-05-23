import Foundation

enum AppConfig {
    /// Google Books API キー (任意)。
    /// 未設定でも匿名で 1,000 req/日 まで使えます。本格運用する場合は
    /// https://console.cloud.google.com/ で API キーを発行し、
    /// Info.plist の `GoogleBooksApiKey` キーに設定してください。
    static var googleBooksApiKey: String? {
        guard let value = Bundle.main.object(forInfoDictionaryKey: "GoogleBooksApiKey") as? String,
              !value.isEmpty,
              value != "YOUR_GOOGLE_BOOKS_API_KEY" else {
            return nil
        }
        return value
    }
}
