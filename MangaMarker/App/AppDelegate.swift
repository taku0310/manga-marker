import UIKit
import BackgroundTasks

/// バックグラウンドでの新刊チェックを担う AppDelegate。
///
/// 動作には Xcode の Signing & Capabilities で **Background Modes → Background fetch** を
/// 有効化する必要があります (Info.plist の `BGTaskSchedulerPermittedIdentifiers` /
/// `UIBackgroundModes` は設定済み)。未設定でも登録/予約は失敗するだけでクラッシュはしません。
final class AppDelegate: NSObject, UIApplicationDelegate {
    static let refreshTaskID = "com.example.MangaMarker.newReleaseRefresh"

    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: Self.refreshTaskID, using: nil) { task in
            guard let refreshTask = task as? BGAppRefreshTask else {
                task.setTaskCompleted(success: false)
                return
            }
            Self.handleRefresh(refreshTask)
        }
        return true
    }

    /// 次回のバックグラウンド新刊チェックを予約する (最短 6 時間後)。
    static func scheduleNewReleaseRefresh() {
        let request = BGAppRefreshTaskRequest(identifier: refreshTaskID)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 6 * 60 * 60)
        try? BGTaskScheduler.shared.submit(request)
    }

    private static func handleRefresh(_ task: BGAppRefreshTask) {
        scheduleNewReleaseRefresh() // 連続実行のため次回分を予約

        let checker = AppDependencies.makeNewReleaseChecker()
        let work = Task {
            await checker.checkAll()
            task.setTaskCompleted(success: !Task.isCancelled)
        }
        task.expirationHandler = { work.cancel() }
    }
}
