import SwiftUI
import UserNotifications

/// 每日定时推送。用本地通知实现，不需要服务器：
/// 一次性排好未来 30 天（iOS 上限 64 条），每次打开 App 或后台任务运行时重排，
/// 因此通知里能带上已经提前生成好的解析导读。
@MainActor
enum NotificationManager {
    nonisolated static let category = "DAILY_POEM"
    nonisolated static let poemIDKey = "poemID"
    private static let idPrefix = "daily-"
    private static let daysAhead = 30
    /// 前几天的通知附带一张诗词卡片图片，展开通知即可看到
    private static let daysWithImage = 5
    /// 改设置时会连续触发重排；只让最后一次生效
    private static var generation = 0

    static var center: UNUserNotificationCenter { .current() }

    static func requestAuthorization() async -> Bool {
        (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
    }

    static func registerCategories() {
        let read = UNNotificationAction(identifier: "READ", title: "阅读解析", options: [.foreground])
        let fav = UNNotificationAction(identifier: "FAVORITE", title: "收藏", options: [])
        center.setNotificationCategories([
            UNNotificationCategory(identifier: category, actions: [read, fav], intentIdentifiers: [])
        ])
    }

    /// 清掉旧的排程，按当前设置重新排未来 30 天
    static func reschedule() async {
        generation += 1
        let current = generation
        let pending = await center.pendingNotificationRequests()
        center.removePendingNotificationRequests(withIdentifiers:
            pending.map(\.identifier).filter { $0.hasPrefix(idPrefix) })

        guard AppSettings.pushEnabled else { return }
        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else { return }

        let calendar = DailyPoemProvider.calendar
        let hour = AppSettings.pushHour, minute = AppSettings.pushMinute
        for (offset, item) in DailyPoemProvider.upcoming(days: daysAhead + 1).enumerated() {
            guard current == generation else { return }
            var comps = calendar.dateComponents([.year, .month, .day], from: item.date)
            comps.hour = hour
            comps.minute = minute
            guard let fireDate = calendar.date(from: comps), fireDate > .now else { continue }

            let content = makeContent(for: item.poem, withImage: offset <= daysWithImage)
            let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
            let id = idPrefix + String(format: "%04d%02d%02d", comps.year ?? 0, comps.month ?? 0, comps.day ?? 0)
            try? await center.add(UNNotificationRequest(identifier: id, content: content, trigger: trigger))
        }
    }

    /// 5 秒后发一条今日的推送，方便在设置里预览效果
    static func sendTest() async {
        guard let poem = DailyPoemProvider.poem(for: .now) else { return }
        let content = makeContent(for: poem, withImage: true)
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 5, repeats: false)
        try? await center.add(UNNotificationRequest(identifier: "test-\(UUID().uuidString)", content: content, trigger: trigger))
    }

    private static func makeContent(for poem: Poem, withImage: Bool) -> UNMutableNotificationContent {
        let content = UNMutableNotificationContent()
        content.title = "今日一词 ·《\(poem.title)》"
        content.subtitle = poem.byline
        if let analysis = AnalysisService.cached(poem.id) {
            content.body = "\(poem.excerpt)\n\n\(analysis.summary)"
        } else {
            content.body = poem.lines.prefix(4).joined(separator: "\n")
        }
        content.sound = .default
        content.categoryIdentifier = category
        content.threadIdentifier = "daily"
        content.userInfo = [poemIDKey: poem.id]
        if withImage, let attachment = cardAttachment(for: poem) {
            content.attachments = [attachment]
        }
        return content
    }

    private static func cardAttachment(for poem: Poem) -> UNNotificationAttachment? {
        guard let data = ShareCardView.pngData(poem: poem, summary: AnalysisService.cached(poem.id)?.summary) else { return nil }
        // 系统会把附件移动到自己的存储里，所以每次写一个新文件
        let url = FileManager.default.temporaryDirectory.appending(path: "card-\(poem.id)-\(UUID().uuidString).png")
        guard (try? data.write(to: url)) != nil else { return nil }
        return try? UNNotificationAttachment(identifier: "card", url: url, options: nil)
    }
}
