import Foundation

enum AppConfig {
    /// 楽天ウェブサービスの applicationId。Info.plist の `RakutenAppId` キーから読み込む。
    /// https://webservice.rakuten.co.jp/ でアプリ登録のうえ取得してください。
    /// 注意: 同じページに UUID 形式の「アフィリエイトID」が併記されますが、
    /// API 認証に使うのは **数字のみの applicationId (通常 19 桁)** です。
    static var rakutenAppId: String? {
        guard let value = Bundle.main.object(forInfoDictionaryKey: "RakutenAppId") as? String,
              !value.isEmpty,
              value != "YOUR_RAKUTEN_APP_ID" else {
            return nil
        }
        #if DEBUG
        if value.contains("-") {
            print("[AppConfig] ⚠️ RakutenAppId にハイフンが含まれています。これは affiliateId (UUID) の可能性が高く、API 認証には使えません。楽天ウェブサービスの「applicationId (数字)」を設定してください。値: \(value)")
        }
        #endif
        return value
    }
}
