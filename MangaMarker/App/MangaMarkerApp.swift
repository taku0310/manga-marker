import SwiftUI

@main
struct MangaMarkerApp: App {
    @StateObject private var dependencies = AppDependencies()
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @Environment(\.scenePhase) private var scenePhase

    init() {
        // AsyncImage (URLSession.shared → URLCache.shared) のカバー画像キャッシュを拡張。
        URLCache.shared = URLCache(memoryCapacity: 32 * 1024 * 1024, diskCapacity: 256 * 1024 * 1024)
        _ = DatabaseManager.shared
    }

    var body: some Scene {
        WindowGroup {
            RootTabView()
                .environmentObject(dependencies)
        }
        .onChange(of: scenePhase) { _, phase in
            // バックグラウンド移行時に新刊チェックの BGTask を予約する。
            if phase == .background {
                AppDelegate.scheduleNewReleaseRefresh()
            }
        }
    }
}

@MainActor
final class AppDependencies: ObservableObject {
    let repository: MangaRepository
    let openBDService: OpenBDService
    let bookSearchService: BookSearchService
    let notificationService: NotificationService
    let newReleaseChecker: NewReleaseChecker

    init() {
        let repo = MangaRepository(db: DatabaseManager.shared)
        let openBD = OpenBDService()
        let bookSearch = Self.makeBookSearchService()
        let notif = NotificationService()
        self.repository = repo
        self.openBDService = openBD
        self.bookSearchService = bookSearch
        self.notificationService = notif
        self.newReleaseChecker = NewReleaseChecker(
            repository: repo,
            openBDService: openBD,
            bookSearchService: bookSearch,
            notificationService: notif
        )
    }

    // MARK: - ViewModel factories (View に DI 詳細を漏らさず生成する)

    func makeMangaListViewModel() -> MangaListViewModel {
        MangaListViewModel(repository: repository, newReleaseChecker: newReleaseChecker)
    }

    func makeSearchViewModel() -> SearchViewModel {
        SearchViewModel(openBDService: openBDService, bookSearchService: bookSearchService, repository: repository)
    }

    func makeMangaDetailViewModel(for manga: Manga) -> MangaDetailViewModel {
        MangaDetailViewModel(
            manga: manga,
            repository: repository,
            openBDService: openBDService,
            newReleaseChecker: newReleaseChecker
        )
    }

    // MARK: - Shared wiring

    /// 検索フロー: 楽天Kobo を第一候補、結果が無ければ Google Books にフォールバック。
    nonisolated static func makeBookSearchService() -> BookSearchService {
        CompositeBookSearchService(primary: RakutenKoboService(), fallback: GoogleBooksService())
    }

    /// バックグラウンド更新など、UI から独立して使う新刊チェッカーを生成する。
    nonisolated static func makeNewReleaseChecker() -> NewReleaseChecker {
        let repo = MangaRepository(db: DatabaseManager.shared)
        return NewReleaseChecker(
            repository: repo,
            openBDService: OpenBDService(),
            bookSearchService: makeBookSearchService(),
            notificationService: NotificationService()
        )
    }
}
