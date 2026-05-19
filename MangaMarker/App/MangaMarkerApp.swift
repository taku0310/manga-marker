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
    let rakutenService: RakutenBooksService
    let notificationService: NotificationService
    let newReleaseChecker: NewReleaseChecker

    init() {
        let repo = MangaRepository(db: DatabaseManager.shared)
        let openBD = OpenBDService()
        let rakuten = RakutenBooksService()
        let notif = NotificationService()
        self.repository = repo
        self.openBDService = openBD
        self.rakutenService = rakuten
        self.notificationService = notif
        self.newReleaseChecker = NewReleaseChecker(
            repository: repo,
            openBDService: openBD,
            rakutenService: rakuten,
            notificationService: notif
        )
    }
}
