import SwiftUI
import UserNotifications

@main
struct MangaMarkerApp: App {
    @StateObject private var dependencies = AppDependencies()

    init() {
        _ = DatabaseManager.shared
    }

    var body: some Scene {
        WindowGroup {
            RootTabView()
                .environmentObject(dependencies)
                .task {
                    await dependencies.notificationService.requestAuthorization()
                    await dependencies.newReleaseChecker.checkAll()
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
        // 検索フロー: 楽天Kobo を第一候補、結果が無ければ Google Books にフォールバック。
        let bookSearch: BookSearchService = CompositeBookSearchService(
            primary: RakutenKoboService(),
            fallback: GoogleBooksService()
        )
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
}
