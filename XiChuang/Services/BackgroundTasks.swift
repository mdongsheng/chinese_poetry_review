import BackgroundTasks
import Foundation

/// 后台任务：在推送之前联网生成接下来几天的解析，然后重排通知，让推送正文带上导读。
enum BackgroundTasks {
    static let prefetchID = "app.xichuang.prefetch"

    static func register() {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: prefetchID, using: nil) { task in
            guard let task = task as? BGProcessingTask else { return }
            schedule()
            let work = Task {
                await AnalysisService.shared.prefetchUpcoming(days: 3)
                await NotificationManager.reschedule()
                task.setTaskCompleted(success: true)
            }
            task.expirationHandler = { work.cancel() }
        }
    }

    /// 请求在下一次推送前约 3 小时运行
    static func schedule() {
        let request = BGProcessingTaskRequest(identifier: prefetchID)
        request.requiresNetworkConnectivity = true
        request.requiresExternalPower = false
        let calendar = DailyPoemProvider.calendar
        var comps = calendar.dateComponents([.year, .month, .day], from: .now)
        comps.hour = AppSettings.pushHour
        comps.minute = AppSettings.pushMinute
        if var next = calendar.date(from: comps) {
            if next <= .now { next = calendar.date(byAdding: .day, value: 1, to: next) ?? next }
            request.earliestBeginDate = max(next.addingTimeInterval(-3 * 3600), .now.addingTimeInterval(15 * 60))
        }
        try? BGTaskScheduler.shared.submit(request)
    }
}
