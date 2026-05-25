# MangaMarker

漫画喫茶ユーザー向けの「既読漫画管理アプリ」(iOS / SwiftUI)。

「何巻まで読んだか分からなくなる」問題を、SQLiteによるローカル管理 + OpenBD / 楽天Kobo / Google Books API
による書誌情報取得・検索で解決します。

---

## 1. アプリ全体アーキテクチャ

### レイヤー構成 (MVVM)

```
┌──────────────────────────────────────────────────────────┐
│                       View (SwiftUI)                     │
│  MangaListView / MangaDetailView / SearchView /          │
│  RootTabView                                             │
└──────────────────────────────────────────────────────────┘
                            │ @StateObject / @Published
┌──────────────────────────────────────────────────────────┐
│                       ViewModel                          │
│  MangaListViewModel / MangaDetailViewModel /             │
│  SearchViewModel                                         │
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

1. **検索** : タイトル / ISBN を入力 → `SearchViewModel.search()` → 楽天Kobo→Google / OpenBD → 結果一覧 → 「＋」でシリーズ全巻を Repository に保存。
2. **既読管理** : 詳細画面で各巻を読了マーク。「ここまで読了」スワイプアクションで一括処理。
3. **次に読む** : `Volume` を `volume_number` 昇順で取り出し、最初の `is_read = 0` をハイライト表示。
4. **新刊通知** : 起動時に `NewReleaseChecker` が登録中シリーズを検索し、未登録かつ最新巻より新しい巻があれば追加 + ローカル通知をスケジュール。

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
│   ├── RootTabView.swift         # 2タブ構成(ライブラリ/検索)
│   └── Info.plist
├── Models/
│   ├── Manga.swift                  # Manga / Volume / MangaWithProgress
│   ├── OpenBDResponse.swift         # OpenBD JSON → OpenBDParsedBook (isbn は Optional)
│   ├── GoogleBooksResponse.swift    # Google Books JSON → OpenBDParsedBook
│   └── RakutenKoboResponse.swift    # 楽天Kobo JSON → OpenBDParsedBook
├── Database/
│   ├── DatabaseManager.swift     # SQLite open / migrate / queue
│   └── MangaRepository.swift     # 全 CRUD
├── Services/
│   ├── AppConfig.swift           # Info.plist 由来の設定値 (RakutenAppId / GoogleBooksApiKey)
│   ├── BookMetadataParser.swift  # 巻数抽出・日付パース・タイトル正規化 (共有)
│   ├── OpenBDService.swift       # ISBN 取得 / バルク取得
│   ├── BookSearchService.swift   # 検索プロトコル + Composite (楽天Kobo→Google フォールバック)
│   ├── RakutenKoboService.swift  # 楽天Kobo電子書籍検索 (第一候補)
│   ├── GoogleBooksService.swift  # Google Books 検索 (フォールバック)
│   ├── NotificationService.swift # UNUserNotificationCenter
│   └── NewReleaseChecker.swift   # 新刊チェック (Composite 検索 + OpenBD 二段構え)
├── ViewModels/
│   ├── MangaListViewModel.swift
│   ├── MangaDetailViewModel.swift
│   └── SearchViewModel.swift
├── Views/
│   ├── MangaListView.swift       # ライブラリ一覧 + 検索 + 次に読む強調
│   ├── MangaDetailView.swift     # 巻一覧 + 「次に読む」カード + スワイプ操作
│   ├── SearchView.swift          # タイトル/ISBN検索 + シリーズ全巻追加
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

### 4-2. タイトル検索 (Composite: 楽天Kobo → Google Books)

OpenBD はタイトル検索ができないため、タイトル/シリーズ検索は **`BookSearchService` プロトコル** に抽象化し、
**`CompositeBookSearchService` が「楽天Kobo を第一候補、結果が空 or エラーなら Google Books にフォールバック」** する構成にしています (`Services/BookSearchService.swift`)。楽天Kobo の方がマンガの取得件数が多い傾向があるため第一候補に採用しています。

```swift
let bookSearch: BookSearchService = CompositeBookSearchService(
    primary: RakutenKoboService(),
    fallback: GoogleBooksService()
)
let books = try await bookSearch.searchByTitle("鬼滅の刃")    // Kobo→Google
let candidates = try await bookSearch.searchSeries("ワンピース")
```

#### 楽天Kobo電子書籍検索API (`Services/RakutenKoboService.swift`)

- エンドポイント: **`https://openapi.rakuten.co.jp/services/api/Kobo/EbookSearch/20170426`** (新 OpenAPI ホスト)
- 認証: **`applicationId` (UUID) と `accessKey` (`pk_` トークン) の両方** が必要。`Info.plist` の `RakutenAppId` / `RakutenAccessKey` から `AppConfig` 経由で取得。**どちらか欠けると `.missingCredentials` を throw → Composite が即 Google にフォールバック**。
- パラメータ: `format=json`, `koboGenreId=101` (コミック), `title`, `hits`, `page`。
- レスポンスは `RakutenKoboResponse` → `RakutenKoboItem.toParsedBook` で正規化。v1 (`{"Item": {...}}` ラップ) / v2 (フラット) の双方を decode 可能。
  - 電子書籍は ISBN を持たないことが多いため、**ISBN が無ければ `itemNumber` を識別子に採用** (`OpenBDParsedBook.isbn` は Optional 化済)。
  - 画像 URL は `http→https` に矯正。

> ⚠️ 旧ホスト `app.rakuten.co.jp` は UUID 形式の applicationId を受け付けず `HTTP 400 specify valid applicationId` を返します。新ホスト `openapi.rakuten.co.jp` + `accessKey` 併用が現行の正しい方式です。

#### Google Books API (`Services/GoogleBooksService.swift`)

- エンドポイント: `https://www.googleapis.com/books/v1/volumes`
- パラメータ: `q=intitle:<キーワード>`, `langRestrict=ja`, `printType=books`, `orderBy=relevance`
- 認証: 匿名は IP ベースで強くスロットルされるため、`Info.plist` の `GoogleBooksApiKey` 設定を推奨。iOS 制限キー対応のため `X-Ios-Bundle-Identifier` ヘッダを自動付与。
- ISBN_13 を優先、無ければ ISBN_10。シリーズ名はタイトルから巻数を除いた残りを推定。

### 4-3. 検索ロジック (SearchViewModel)

- **自動モード** (デフォルト): 入力が「数字+ハイフン+空白のみ」かつ桁数が 10 または 13 のときは ISBN → OpenBD 検索。それ以外は Composite (楽天Kobo→Google) タイトル検索。
- **ISBN モード**: 強制的に OpenBD 検索 (失敗時は Composite の `isbn:` 検索にフォールバック)。
- **タイトルモード**: 強制的に Composite タイトル検索。

#### 検索結果のシリーズ集約と全巻登録

- 検索結果は `SeriesVolumeFilter.representatives` で **シリーズ単位に集約し、各シリーズ代表 1 件 (最小巻) のみ** を表示する (巻数バッジは非表示)。例: 「鬼滅」→ `鬼滅の刃` 1 行のみ。
- 集約・全巻照合のキーには `OpenBDParsedBook.seriesTitle` を使う。API の `series` フィールドが空の場合は **タイトルから巻数表記を除去 (`BookMetadataParser.stripVolumeSuffix`)** してクリーンなシリーズ名を導出する。これにより `series` 未提供の作品でも「全巻」ではなく「代表のみ」になってしまう取りこぼしを防ぐ。
- 結果行の「＋」を押すと `searchAllVolumes(seriesName:)` でそのシリーズの全巻をページネーション取得し、`volumes` テーブルへ一括登録する (取得失敗時は代表のみ登録)。全巻取得は楽天Kobo / Google Books それぞれ最大 6 ページ (最大 180〜240 巻)。
- **ページネーションの打ち切り**: 楽天 API は最終ページの次を要求すると 404/`not_found` を返すため、各ページの取得エラーは throw せず「打ち切り」として扱い、それまでに集めた巻を活かす。これをしないと最後のページのエラーで全巻が破棄され「代表のみ登録」になる。DEBUG ビルドでは `searchAllVolumes(...): collected=X volumes=Y` を出力して取得・抽出件数を確認できる。
- **レート制限対策 (歯抜け防止)**: 楽天はおよそ 1 req/秒の制限があり、連続ページ取得で `HTTP 429` が返ると途中のページが欠落して巻が歯抜けになる。対策として **(1) ページ間にウェイト (楽天 0.8s / Google 0.3s) を挿入**し、**(2) 429 は打ち切らず指数バックオフ (1→2→4→8s) で最大 4 回リトライ**する。404 等の末尾超過のみ打ち切り、と区別している。Kobo の検索結果は巻順とは限らないため、全ページを取得し `SeriesVolumeFilter.allVolumes` が巻数で重複排除・整列することで全巻を揃える。

### 4-4. 新刊検出 (`Services/NewReleaseChecker.swift`)

二段構えで精度を確保:

1. **Composite シリーズ検索** (主): `searchSeries(manga.title)` (楽天Kobo→Google) → 同一シリーズ判定 → 未登録かつ最新巻より新しい発売日のみ採用。
2. **OpenBD ISBN 近傍探索** (フォールバック): Composite が一件もヒットしない場合、最新巻 ISBN の隣接 8 件を OpenBD でバッチ取得。

採用時は `volumes` テーブルへ自動登録 + `UNCalendarNotificationTrigger` でローカル通知を予約 + `notifications_log` で冪等性を担保。ISBN が無いソースでは `OpenBDParsedBook.id` (タイトル+著者+巻数) を冪等キーに使用。

同一シリーズ判定は `BookMetadataParser.normalizeTitle` (空白除去 + 小文字化 + `・` 除去) を用いた双方向部分一致。既知巻数と重複するもの (廉価版・愛蔵版など) は除外する。

---

## 5. 将来拡張

- ~~**タイトル検索**~~ → **実装済** (楽天Kobo→Google Books)
- ~~**新刊検出の精度向上**~~ → **実装済** (Composite シリーズ検索 + OpenBD 近傍 ISBN フォールバック)
- **バーコードスキャン登録** : `AVFoundation` で ISBN を読み取り自動登録 (一度実装したが要件外のため削除済。再導入時は `NSCameraUsageDescription` の追加が必要)。
- **iCloud / CloudKit 同期** : `manga` `volumes` を `CKRecord` でミラーし、
  複数端末・データ移行に対応。SQLite はキャッシュレイヤー化。
- **WidgetKit / Live Activities** : ホーム画面に「次に読む」カードを常時表示。
- **App Intents / Siri Shortcuts** : 「次に読む巻を教えて」発話で読み上げ。
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
4. `Info.plist` を本リポジトリのものに置き換え (API キー類を設定)。
5. Deployment Target を **iOS 17.0** 以上に。
6. シミュレータ / 実機いずれでもビルド・動作可能 (カメラ等のハード依存機能は無し)。

### Google Books API のセットアップ (実質必須)

タイトル検索と新刊検出は Google Books API を利用します。コード上は `GoogleBooksApiKey` 未設定でも動きますが、**Google は匿名アクセスを IP 単位で強くスロットルしており、シミュレータからは数回〜数十回で `HTTP 429 rateLimitExceeded` が返ります**。実用するには無料の API キー (個人プロジェクトのクォータ 100,000 req/日) を取得してください。

1. [Google Cloud Console](https://console.cloud.google.com/) でプロジェクト作成 (例: `manga-marker`)
2. 「APIとサービス」→「ライブラリ」→ **「Books API」を検索 → 有効化**
3. 「APIとサービス」→「認証情報」→ 「認証情報を作成」→ **「API キー」**
4. **(推奨) 「キーを制限」→ アプリケーションの制限 → 「iOS アプリ」** を選び、**`MangaMarker/App/Info.plist` 内の Bundle ID と完全一致する値** (デフォルトは `com.example.MangaMarker`) を追加。
5. Xcode で `MangaMarker/App/Info.plist` を開き、`GoogleBooksApiKey` の値を発行された API キー (`AIzaSy...`) に置換
6. Product → Clean Build Folder → Build & Run

> 本アプリは API リクエストに `X-Ios-Bundle-Identifier` ヘッダを自動付与するので、iOS アプリ制限つき API キーがそのまま使えます。
> Bundle ID を変更している場合は、Google Cloud Console の制限リストにも同じ値を追加してください。一致していないと `HTTP 403 API_KEY_IOS_APP_BLOCKED` で弾かれます。

> 未設定でも検索リクエスト自体は飛びますが、ほぼ確実にレート制限に当たります。エラーメッセージ「Google Books API のアクセス制限に達しました。匿名利用は IP ベースで強く制限されます。」が出たら API キー設定をしてください。

### 楽天Kobo API のセットアップ (任意・第一候補)

検索の第一候補は楽天Kobo電子書籍検索API です。**`RakutenAppId` と `RakutenAccessKey` の両方** を設定すると楽天Kobo を優先的に検索し、ヒットしなければ自動的に Google Books へフォールバックします。**どちらか未設定の場合は楽天Kobo をスキップし、Google Books のみで動作します**。

1. https://webservice.rakuten.co.jp/ でアプリ登録
2. アプリ詳細から以下の **2 つ** をコピー
   - **アプリケーションID** (UUID 形式、例 `8738d9c9-...`)
   - **アクセスキー** (`pk_` プレフィックス、目玉アイコンで表示)
3. Xcode で `MangaMarker/App/Info.plist` を開き
   - `RakutenAppId` ← アプリケーションID
   - `RakutenAccessKey` ← アクセスキー
4. Product → Clean Build Folder → Build & Run

> 現行の楽天 OpenAPI は **新ホスト `openapi.rakuten.co.jp` + `applicationId` + `accessKey`** の組み合わせで認証します。旧ホスト `app.rakuten.co.jp` は UUID 形式を受け付けず `HTTP 400 specify valid applicationId` を返すため使用しません。
> 設定が誤っていても Composite が Google Books にフォールバックするため検索自体は継続動作します (コンソールに `[RakutenKobo] HTTP 400 ...` が出ます)。

### 検索フローまとめ

| モード | 1st | 2nd | 3rd |
|--------|-----|-----|-----|
| タイトル | 楽天Kobo (`RakutenAppId`+`RakutenAccessKey` 設定時) | Google Books | — |
| ISBN | OpenBD | 楽天Kobo→Google の `isbn:` 検索 | — |
| 新刊検出 | 楽天Kobo→Google シリーズ検索 | OpenBD ISBN 近傍 | — |

### トラブルシューティング

ビルド済みアプリの Info.plist が想定どおり反映されているか確認:

```bash
plutil -p ~/Library/Developer/Xcode/DerivedData/MangaMarker-*/Build/Products/Debug-iphonesimulator/MangaMarker.app/Info.plist | grep -i google
```

| 症状 | 原因 | 対処 |
|------|------|------|
| 何も検索結果が返らない | 入力タイトルの表記揺れ (旧字体・空白) | 別表記で試す。`langRestrict=ja` で日本語結果のみに制限済 |
| 同じシリーズが大量に重複表示 | Google Books は出版社違いの再販版を別レコードで返す | 「ライブラリに追加」時には ISBN が一致するものは upsert で 1 件に集約される |
| HTTP 429 / 403 rateLimitExceeded | **匿名アクセスは Google 側で IP ベースで強くスロットルされ、数回で 429 になる** | `GoogleBooksApiKey` を設定 (上記セットアップ手順) してプロジェクト単位のクォータ 100,000 req/日 を使う |
| HTTP 403 API_KEY_IOS_APP_BLOCKED | API キーに iOS アプリ制限を掛けたが、リクエストヘッダの Bundle ID と Google Cloud Console の制限リストが一致していない | コード側は `X-Ios-Bundle-Identifier` を自動付与済 (DEBUG ログで確認可能)。Cloud Console の制限リストに **Info.plist と完全一致する Bundle ID** を追加。Bundle ID を変更した場合も同じ |
| `xcodegen generate` の度に Info.plist が初期化される | (修正済) | 本リポジトリの `project.yml` は `info:` ブロック未使用。古い構成を使っている場合は同様に削除 |
| Clean Build が必要 | DerivedData に古い Info.plist がキャッシュ | Xcode → Product → Clean Build Folder (`⇧⌘K`) |

### 動作確認

- 検索タブで「タイトル」モードに切り替え `鬼滅の刃` などを入力 → シリーズ代表 1 件が返り、「＋」で全巻登録。
- 検索タブで「ISBN」モードに切り替え `9784088831824` を入力 → OpenBD で取得。
- 「自動」モードでは入力を見て自動で振り分け。
- ライブラリタブで進捗バーと「次に読む」バッジが表示される。
- 詳細画面で巻をタップして読了マーク、または左スワイプで「ここまで読了」。
- アプリ起動 + ライブラリ画面で Pull to Refresh → Google Books シリーズ検索による新刊チェックが走り、新刊が見つかれば自動で巻が追加され通知が予約される。

---

## ライセンス

MIT。OpenBD API の利用は OpenBD の利用規約に従ってください。
