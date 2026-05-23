import Foundation

enum AppConfig {
    /// 楽天ウェブサービスで API 認証に使う値。Info.plist の `RakutenAppId` キーから読み込む。
    /// https://webservice.rakuten.co.jp/ でアプリ登録のうえ取得。
    ///
    /// ⚠️ 注意:
    /// - ダッシュボードに表示される **アプリケーションID** (UUID 形式) を渡しても
    ///   API が `wrong_parameter ("specify valid applicationId")` を返すケースが報告されています。
    /// - その場合は **アクセスキー** (目玉アイコンで表示できる秘密トークン) を設定してください。
    /// - 古いドキュメントには「19 桁の数字」と書かれている場合がありますが、これは旧仕様です。
    static var rakutenAppId: String? {
        guard let value = Bundle.main.object(forInfoDictionaryKey: "RakutenAppId") as? String,
              !value.isEmpty,
              value != "YOUR_RAKUTEN_APP_ID" else {
            return nil
        }
        return value
    }
}
