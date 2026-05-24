import Foundation

enum AppConfig {
    /// 楽天ウェブサービスの applicationId。Info.plist の `RakutenAppId` キーから読み込む。
    /// 楽天Kobo電子書籍検索API の認証に使用。未設定なら楽天検索はスキップし Google Books のみ動作。
    static var rakutenAppId: String? {
        guard let value = Bundle.main.object(forInfoDictionaryKey: "RakutenAppId") as? String,
              !value.isEmpty,
              value != "YOUR_RAKUTEN_APP_ID" else {
            return nil
        }
        return value
    }

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
