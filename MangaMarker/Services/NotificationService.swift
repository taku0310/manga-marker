import Foundation
import UserNotifications

final class NotificationService: @unchecked Sendable {
    /// 通知許可が未確定なら要求する (確定済みなら何もしない)。初回スケジュール時に文脈付きで呼ぶ。
    @discardableResult
    func ensureAuthorization() async -> Bool {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            return true
        case .denied:
            return false
        case .notDetermined:
            return (try? await center.requestAuthorization(options: [.alert, .badge, .sound])) ?? false
        @unknown default:
            return false
        }
    }

    func scheduleNewReleaseNotification(mangaTitle: String, volumeNumber: Int, isbn: String, releaseDate: Date) async {
        // 実際に通知する必要が生じた時点で (新刊検出時) 文脈付きで許可を要求する。
        guard await ensureAuthorization() else { return }

        let content = UNMutableNotificationContent()
        content.title = "新刊が登場しました"
        content.body = "『\(mangaTitle)』\(volumeNumber)巻が発売されました"
        content.sound = .default
        content.userInfo = ["isbn": isbn]

        let trigger: UNNotificationTrigger
        if releaseDate > Date() {
            let comps = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: releaseDate)
            trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
        } else {
            trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        }

        let request = UNNotificationRequest(identifier: "new-release-\(isbn)", content: content, trigger: trigger)
        try? await UNUserNotificationCenter.current().add(request)
    }
}
