import Foundation
import UserNotifications

final class NotificationService {
    func requestAuthorization() async {
        do {
            _ = try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound])
        } catch {
            print("Notification auth failed: \(error)")
        }
    }

    func scheduleNewReleaseNotification(mangaTitle: String, volumeNumber: Int, isbn: String, releaseDate: Date) async {
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
