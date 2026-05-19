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
│   └── OpenBDResponse.swift      # OpenBD JSON → OpenBDParsedBook
├── Database/
│   ├── DatabaseManager.swift     # SQLite open / migrate / queue
│   └── MangaRepository.swift     # 全 CRUD
├── Services/
│   ├── OpenBDService.swift       # ISBN取得 / バルク取得 / パース
│   ├── NotificationService.swift # UNUserNotificationCenter
│   └── NewReleaseChecker.swift   # 新刊チェックロジック
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

## 4. API 通信コード (OpenBD)

`Services/OpenBDService.swift` 参照。

- エンドポイント: `https://api.openbd.jp/v1/get?isbn=...`
- バルク取得対応 (カンマ区切り) → `fetch(isbns:)`。
- レスポンスは `[OpenBDBook?]` 形式 (null を含む配列) を `compactMap` でクレンジング。
- `summary.volume` または `title` から正規表現で巻数を抽出 (`(?:第)?(\d+)\s*巻` 等)。
- `pubdate` (`yyyyMMdd` 等) を JST で `Date` へ変換。
- エラーは `OpenBDError` 列挙体で表現し、`LocalizedError` で UI 表示用に整形。

### 呼び出し例

```swift
let book = try await openBDService.fetch(isbn: "9784088831824")
print(book.title, book.volumeNumber, book.coverImageURL)
```

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

- **タイトル検索** : OpenBD はタイトル検索 API がないため、Google Books API
  もしくは楽天ブックス書籍検索 API を `OpenBDService` と並列に注入する。
  `BookSearchService` プロトコルを切って抽象化 (SOLID)。
- **新刊検出の精度向上** : 出版社別シリーズコード (JAN 内部の出版社識別) を辞書化、
  あるいは Amazon PA-API・楽天ブックス API による「シリーズ ID → 全巻リスト」取得に切替。
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

### 動作確認

- 検索タブで `9784088831824` (例: 集英社のあるコミックス) を入力 → 検索 → 追加。
- スキャンタブで書籍裏表紙のバーコードをかざす → 自動追加。
- ライブラリタブで進捗バーと「次に読む」バッジが表示される。
- 詳細画面で巻をタップして読了マーク、または左スワイプで「ここまで読了」。

---

## ライセンス

MIT。OpenBD API の利用は OpenBD の利用規約に従ってください。
