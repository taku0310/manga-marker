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
    let bookSearchService: GoogleBooksService
    let notificationService: NotificationService
    let newReleaseChecker: NewReleaseChecker

    init() {
        let repo = MangaRepository(db: DatabaseManager.shared)
        let openBD = OpenBDService()
        let googleBooks = GoogleBooksService()
        let notif = NotificationService()
        self.repository = repo
        self.openBDService = openBD
        self.bookSearchService = googleBooks
        self.notificationService = notif
        self.newReleaseChecker = NewReleaseChecker(
            repository: repo,
            openBDService: openBD,
            bookSearchService: googleBooks,
            notificationService: notif
        )
    }
}
