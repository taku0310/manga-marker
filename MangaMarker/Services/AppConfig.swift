import Foundation

enum AppConfig {
    /// 楽天ウェブサービスの applicationId。Info.plist の `RakutenAppId` キーから読み込む。
    /// https://webservice.rakuten.co.jp/ でアプリ登録のうえ取得してください。
    static var rakutenAppId: String? {
        guard let value = Bundle.main.object(forInfoDictionaryKey: "RakutenAppId") as? String,
              !value.isEmpty,
              value != "YOUR_RAKUTEN_APP_ID" else {
            return nil
        }
        return value
    }
}
