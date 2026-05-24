import Foundation

enum AppConfig {
    /// 楽天ウェブサービスの applicationId (UUID 形式)。Info.plist の `RakutenAppId` から読み込む。
    /// 新しい楽天 OpenAPI (openapi.rakuten.co.jp) では accessKey とセットで使用する。
    static var rakutenAppId: String? {
        value(forKey: "RakutenAppId", placeholder: "YOUR_RAKUTEN_APP_ID")
    }

    /// 楽天 OpenAPI の accessKey (`pk_` プレフィックス)。Info.plist の `RakutenAccessKey` から読み込む。
    static var rakutenAccessKey: String? {
        value(forKey: "RakutenAccessKey", placeholder: "YOUR_RAKUTEN_ACCESS_KEY")
    }

    /// Google Books API キー (任意)。
    /// 未設定でも匿名で 1,000 req/日 まで使えます。本格運用する場合は
    /// https://console.cloud.google.com/ で API キーを発行し、
    /// Info.plist の `GoogleBooksApiKey` キーに設定してください。
    static var googleBooksApiKey: String? {
        value(forKey: "GoogleBooksApiKey", placeholder: "YOUR_GOOGLE_BOOKS_API_KEY")
    }

    /// Info.plist から文字列値を読み込む。空文字 / プレースホルダは nil 扱い。
    private static func value(forKey key: String, placeholder: String) -> String? {
        guard let value = Bundle.main.object(forInfoDictionaryKey: key) as? String,
              !value.isEmpty,
              value != placeholder else {
            return nil
        }
        return value
    }
}
