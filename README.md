# MangaMarker

漫画喫茶ユーザー向けの「既読漫画管理アプリ」(iOS / SwiftUI)。

「何巻まで読んだか分からなくなる」問題を、SQLiteによるローカル管理 + OpenBD API
による書誌情報取得 + バーコードスキャンで解決します。

---

## 1. アプリ全体アーキテクチャ

### レイヤー構成 (MVVM)

```
┌──────────────────────────────────────────────────────────┐
│                       View (SwiftUI)                     │
│  MangaListView / MangaDetailView / SearchView /          │
│  BarcodeScannerView / RootTabView                        │
└──────────────────────────────────────────────────────────┘
                            │ @StateObject / @Published
┌──────────────────────────────────────────────────────────┐
│                       ViewModel                          │
│  MangaListViewModel / MangaDetailViewModel /             │
│  SearchViewModel / BarcodeScannerViewModel               │
└──────────────────────────────────────────────────────────┘
            │ Repository                  │ Service
┌────────────────────────────┐   ┌──────────────────────────┐
│   MangaRepository (SQLite) │   │  OpenBDService (URLSess) │
│   DatabaseManager          │   │  NotificationService     │
│                            │   │  NewReleaseChecker       │
└────────────────────────────┘   └──────────────────────────┘
            │                                │
        ┌───────────┐                ┌──────────────────┐
        │ SQLite DB │                │   OpenBD API     │
        │ (local)   │                │ api.openbd.jp/v1 │
        └───────────┘                └──────────────────┘
```

- **View** は状態と入力ハンドリングのみ。ロジックはすべて ViewModel に集約。
- **ViewModel** は `@MainActor` 指定で、UI 状態 (@Published) と repository/service の呼び出しに専念。
- **Repository** が SQLite との CRUD を一手に担当 (生 SQLite3 を薄くラップ)。
- **Service** は外部 I/O (HTTP、通知、新刊チェック) を担当。
- **DI** は `AppDependencies` で集約し、`@EnvironmentObject` で配布。
- **並行性** : Repository は `DispatchQueue.sync` 直列化、Service は async/await。

### 主要フロー

1. **検索** : ISBN を入力 → `SearchViewModel.search()` → OpenBD → 結果一覧 → タップで Repository に保存。
2. **スキャン** : `AVCaptureSession` (EAN-13/EAN-8/UPC-E) → ISBN を取得 → OpenBD で詳細取得 → ライブラリへ追加。
3. **既読管理** : 詳細画面で各巻を読了マーク。「ここまで読了」スワイプアクションで一括処理。
4. **次に読む** : `Volume` を `volume_number` 昇順で取り出し、最初の `is_read = 0` をハイライト表示。
5. **新刊通知** : 起動時に `NewReleaseChecker` が登録中シリーズの最新 ISBN を基点に近接 ISBN を OpenBD に問い合わせ、同シリーズかつ未登録なら追加 + ローカル通知をスケジュール。

---

## 2. DB 設計

SQLite を直接利用（外部依存なし）。WAL + 外部キー有効化。

### `manga` テーブル

| カラム            | 型        | 説明                            |
|-------------------|-----------|---------------------------------|
| id                | INTEGER PK| AUTOINCREMENT                   |
| title             | TEXT      | シリーズタイトル                |
| author            | TEXT      | 著者                            |
| publisher         | TEXT?     | 出版社                          |
| cover_image_url   | TEXT?     | カバー画像URL                   |
| total_volumes     | INTEGER?  | 既知の総巻数（任意）            |
| is_completed      | INTEGER   | 完結フラグ(0/1)                 |
| created_at        | REAL      | UNIX time                       |
| updated_at        | REAL      | UNIX time                       |

### `volumes` テーブル

| カラム            | 型        | 説明                                       |
|-------------------|-----------|--------------------------------------------|
| id                | INTEGER PK| AUTOINCREMENT                              |
| manga_id          | INTEGER FK| `manga(id)` ON DELETE CASCADE              |
| volume_number     | INTEGER   | 巻数                                       |
| isbn              | TEXT?     | ISBN-13                                    |
| title             | TEXT?     | 巻タイトル                                 |
| cover_image_url   | TEXT?     | 表紙画像URL                                |
| published_at      | REAL?     | 発売日                                     |
| is_read           | INTEGER   | 0/1                                        |
| read_at           | REAL?     | 読了日時                                   |
| created_at        | REAL      | UNIX time                                  |
| UNIQUE(manga_id, volume_number) |  | 同一巻の重複防止                  |

### `notifications_log`

| カラム      | 型     | 説明                                |
|-------------|--------|-------------------------------------|
| isbn        | TEXT PK| 通知済み ISBN                       |
| notified_at | REAL   | 通知日時                            |

### インデックス

- `idx_volumes_manga_id` (manga_id)
- `idx_volumes_isbn` (isbn)

### 「次に読む巻」クエリ (Repository で実装)

```sql
SELECT * FROM volumes
 WHERE manga_id = ? AND is_read = 0
 ORDER BY volume_number ASC
 LIMIT 1;
```

---

## 3. SwiftUI コード構成

```
MangaMarker/
├── App/
│   ├── MangaMarkerApp.swift      # @main, DI(AppDependencies), 起動時の処理
│   ├── RootTabView.swift         # 3タブ構成(ライブラリ/検索/スキャン)
│   └── Info.plist
├── Models/
│   ├── Manga.swift               # Manga / Volume / MangaWithProgress
│   ├── OpenBDResponse.swift      # OpenBD JSON → OpenBDParsedBook
│   └── RakutenResponse.swift     # 楽天ブックス JSON → OpenBDParsedBook
├── Database/
│   ├── DatabaseManager.swift     # SQLite open / migrate / queue
│   └── MangaRepository.swift     # 全 CRUD
├── Services/
│   ├── AppConfig.swift           # Info.plist 由来の設定値 (RakutenAppId)
│   ├── BookMetadataParser.swift  # 巻数抽出・日付パース・タイトル正規化 (共有)
│   ├── OpenBDService.swift       # ISBN 取得 / バルク取得
│   ├── RakutenBooksService.swift # タイトル検索 / シリーズ検索
│   ├── NotificationService.swift # UNUserNotificationCenter
│   └── NewReleaseChecker.swift   # 新刊チェック (楽天 + OpenBD 二段構え)
├── ViewModels/
│   ├── MangaListViewModel.swift
│   ├── MangaDetailViewModel.swift
│   ├── SearchViewModel.swift
│   └── BarcodeScannerViewModel.swift
├── Views/
│   ├── MangaListView.swift       # ライブラリ一覧 + 検索 + 次に読む強調
│   ├── MangaDetailView.swift     # 巻一覧 + 「次に読む」カード + スワイプ操作
│   ├── SearchView.swift          # ISBN検索 + ライブラリ追加
│   ├── BarcodeScannerView.swift  # AVCapture + 結果オーバーレイ
│   └── Components/
│       └── MangaRowView.swift    # 行表示 + AsyncImage + Progress
└── Resources/
    └── Assets.xcassets/
```

UI のキーポイント:

- **「次に読む」強調** : 詳細画面で専用カード + `accentColor.opacity(0.08)` 背景 +
  リスト行に `NEXT` バッジ。一覧画面では `NextVolumeBadge` を行内に表示。
- **進捗** : `ProgressView(value:)` で読了率を可視化。
- **スワイプ** : 左スワイプで「ここまで読了」、右で削除。
- **状態空表示** : `ContentUnavailableView`。

---

## 4. API 通信コード

### 4-1. OpenBD (`Services/OpenBDService.swift`)

- エンドポイント: `https://api.openbd.jp/v1/get?isbn=...`
- バルク取得対応 (カンマ区切り) → `fetch(isbns:)`。
- レスポンスは `[OpenBDBook?]` 形式 (null を含む配列) を `compactMap` でクレンジング。
- 巻数・発売日のパースは `BookMetadataParser` に集約。
- エラーは `OpenBDError` 列挙体で表現し、`LocalizedError` で UI 表示用に整形。

```swift
let book = try await openBDService.fetch(isbn: "9784088831824")
```

### 4-2. 楽天ブックス (`Services/RakutenBooksService.swift`)

OpenBD はタイトル検索ができないため、**楽天ブックス書籍検索 API** をタイトル検索とシリーズ検索に併用。

- エンドポイント: `https://app.rakuten.co.jp/services/api/BooksBook/Search/20170404`
- `applicationId` は **`Info.plist` の `RakutenAppId` キー** から `AppConfig` 経由で読み取る。
- マンガジャンル (`booksGenreId=001001`) に限定 + 発売日降順 (`sort=-releaseDate`) で取得。
- レスポンスは `RakutenSearchResponse` で受け、`RakutenItem.toParsedBook` で `OpenBDParsedBook` に正規化 (画像 URL は `https` に自動置換)。
- 公開メソッド:
  - `searchByTitle(_:)`: タイトル/著者/キーワード検索 (SearchView 用)
  - `searchSeries(_:)`: シリーズ名検索 → クライアント側で seriesName 一致フィルタ (NewReleaseChecker 用)

```swift
let books = try await rakutenService.searchByTitle("鬼滅の刃")
let candidates = try await rakutenService.searchSeries("ワンピース")
```

**applicationId 取得**: [楽天ウェブサービス](https://webservice.rakuten.co.jp/) でアプリ登録 (無料) → Info.plist の `RakutenAppId` を発行された ID に置換。未設定でもアプリは起動でき、検索時にエラーメッセージで案内します。

### 4-3. 検索ロジック (SearchViewModel)

- **自動モード** (デフォルト): 入力が「数字+ハイフン+空白のみ」かつ桁数が 10 または 13 のときは ISBN → OpenBD 検索。それ以外は楽天タイトル検索。
- **ISBN モード**: 強制的に OpenBD 検索 (失敗時は楽天にフォールバック)。
- **タイトルモード**: 強制的に楽天タイトル検索。

### 4-4. 新刊検出 (`Services/NewReleaseChecker.swift`)

二段構えで精度を確保:

1. **楽天シリーズ検索** (主): `searchSeries(manga.title)` → 同一シリーズ判定 → 未登録 ISBN かつ最新巻より新しい発売日のみ採用。
2. **OpenBD ISBN 近傍探索** (フォールバック): 楽天 API が使えない / ヒットなしの場合、最新巻 ISBN の隣接 8 件を OpenBD でバッチ取得。

採用時は `volumes` テーブルへ自動登録 + `UNCalendarNotificationTrigger` でローカル通知を予約 + `notifications_log` で冪等性を担保。

同一シリーズ判定は `BookMetadataParser.normalizeTitle` (空白除去 + 小文字化 + `・` 除去) を用いた双方向部分一致。既知巻数と重複するもの (廉価版・愛蔵版など) は除外する。

---

## 5. バーコードスキャン実装

`Views/BarcodeScannerView.swift` 参照。

- `AVCaptureSession` + `AVCaptureMetadataOutput`、対応コード: `.ean13`, `.ean8`, `.upce`。
- `UIViewControllerRepresentable` で SwiftUI に橋渡し。
- 1.5 秒以内の連続スキャンを抑止し、`UINotificationFeedbackGenerator` でハプティック。
- 取得した文字列が `978`/`979` 始まりの 13 桁数字であれば書籍 ISBN と判定 → ViewModel に通知。
- `Info.plist` に `NSCameraUsageDescription` を設定 (本リポジトリで設定済み)。

### Info.plist 設定

```xml
<key>NSCameraUsageDescription</key>
<string>漫画のバーコードを読み取り、書誌情報を自動取得するためにカメラを使用します。</string>
```

---

## 6. 将来拡張

- ~~**タイトル検索**~~ → **実装済** (楽天ブックス書籍検索 API)
- ~~**新刊検出の精度向上**~~ → **実装済** (楽天シリーズ検索 + OpenBD 近傍 ISBN フォールバック)
- **iCloud / CloudKit 同期** : `manga` `volumes` を `CKRecord` でミラーし、
  複数端末・データ移行に対応。SQLite はキャッシュレイヤー化。
- **WidgetKit / Live Activities** : ホーム画面に「次に読む」カードを常時表示。
- **App Intents / Siri Shortcuts** : 「次に読む巻を教えて」発話で読み上げ。
- **OCR フォールバック** : バーコードが汚れている場合、Vision で背表紙テキスト OCR。
- **共有ライブラリ** : 漫画喫茶店内の友人と読書状況を共有 (CloudKit Sharing)。
- **ダーク/ライト最適化** + アクセシビリティ (Dynamic Type、VoiceOver ラベル整備)。
- **テスト** : `MangaRepositoryTests` を出発点に、`OpenBDService` をプロトコル化して URLProtocol スタブで網羅。
- **CI** : GitHub Actions で `xcodebuild test` を回す。

---

## セットアップ手順

### A. XcodeGen を使う場合 (推奨)

```bash
brew install xcodegen
cd manga-marker
xcodegen generate
open MangaMarker.xcodeproj
```

### B. 手動で Xcode プロジェクトを作る場合

1. Xcode で **iOS → App → Interface: SwiftUI / Language: Swift** で新規プロジェクトを `MangaMarker` 名で作成。
2. 既定生成された `ContentView.swift` 等を削除し、本リポジトリの `MangaMarker/` 配下を全てコピー (フォルダ参照ではなくグループとして追加)。
3. Target → **Frameworks, Libraries, and Embedded Content** に `libsqlite3.tbd` を追加。
4. `Info.plist` を本リポジトリのものに置き換え (またはキー `NSCameraUsageDescription` を追記)。
5. Deployment Target を **iOS 17.0** 以上に。
6. **実機** でカメラ機能を確認 (シミュレーターはバーコードスキャン非対応)。

### 楽天 API のセットアップ

タイトル検索と高精度な新刊検出を有効化するには、楽天ウェブサービスの applicationId が必要です。

1. https://webservice.rakuten.co.jp/ で会員登録 (Rakuten ID) → 「アプリ ID 発行」。
2. Xcode で `MangaMarker/App/Info.plist` を開き、`RakutenAppId` の値を発行された ID に置き換え。
3. Build & Run。

> 未設定でもアプリは起動できますが、タイトル検索時にエラーメッセージで案内され、新刊検出は ISBN 近傍フォールバックのみで動作します。

### トラブルシューティング: applicationId 設定済なのにエラーが出る

`Info.plist` の `RakutenAppId` を設定したのに「applicationId が設定されていません」と表示される場合、ビルドされた `.app` バンドル内の `Info.plist` にキーが反映されていない可能性が高いです。次のコマンドで確認できます。

```bash
plutil -p ~/Library/Developer/Xcode/DerivedData/MangaMarker-*/Build/Products/Debug-iphonesimulator/MangaMarker.app/Info.plist | grep -i rakuten
```

何も出力されない場合、原因の多くは以下のいずれかです。

| 症状 | 原因 | 対処 |
|------|------|------|
| `xcodegen generate` の度に Info.plist が初期化される | `project.yml` の `info:` ディレクティブが指定先パスに新しい Info.plist を**生成・上書き**するため | 本リポジトリの `project.yml` は `info:` を使わず `INFOPLIST_FILE` で参照のみする構成に修正済。古い `project.yml` を使っている場合は `info:` ブロックを削除して再生成 |
| 手動セットアップで Info.plist が `INFOPLIST_FILE` に設定されていない | Target → Build Settings の `INFOPLIST_FILE` が空 / 別のパスを指す | Build Settings で `INFOPLIST_FILE = MangaMarker/App/Info.plist` を明示 |
| プレースホルダのまま | `RakutenAppId` の値が `YOUR_RAKUTEN_APP_ID` のまま | 実 ID に置換 (空文字や `YOUR_RAKUTEN_APP_ID` は `AppConfig` で nil 扱い) |
| Clean Build が必要 | DerivedData に古い Info.plist がキャッシュ | Xcode → Product → Clean Build Folder (`⇧⌘K`) して再ビルド |

### トラブルシューティング: HTTP 400 (wrong_parameter) が出る

`RakutenBooksService` で 400 が返るときは、レスポンスボディに楽天 API の `error_description` が含まれます。本リポジトリでは:

- DEBUG ビルド時にコンソールへ `[Rakuten] GET <URL>` と `[Rakuten] HTTP 400 body: <JSON>` を出力
- UI 上は `HTTPエラー 400: <error_description>` の形でアラート表示

過去に確認された原因例:

- `booksGenreId=001001` を渡していた → 楽天ブックスでは `001001` は「文芸書」で、API バージョンによってはマンガタイトル検索と組み合わせると `wrong_parameter` を返す。 → **本リポジトリでは genre 絞り込みを廃止し、結果はクライアント側で発売日降順にソートする方式に変更済**。

### 動作確認

- 検索タブで「タイトル」モードに切り替え `鬼滅の刃` などを入力 → 楽天 API でシリーズの全巻が並ぶ。
- 検索タブで「ISBN」モードに切り替え `9784088831824` を入力 → 1 件取得。
- 「自動」モードでは入力を見て自動で振り分け。
- スキャンタブで書籍裏表紙のバーコードをかざす → 自動追加。
- ライブラリタブで進捗バーと「次に読む」バッジが表示される。
- 詳細画面で巻をタップして読了マーク、または左スワイプで「ここまで読了」。
- アプリ起動 + ライブラリ画面で Pull to Refresh → 楽天シリーズ検索による新刊チェックが走り、新刊が見つかれば自動で巻が追加され通知が予約される。

---

## ライセンス

MIT。OpenBD API の利用は OpenBD の利用規約に従ってください。
