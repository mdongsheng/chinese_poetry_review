import SwiftUI
import UserNotifications

@main
struct XiChuangApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @Environment(\.scenePhase) private var scenePhase
    @State private var router = Router.shared

    init() {
        AppSettings.registerDefaults()
        Theme.registerFonts()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(router)
                .environment(FavoritesStore.shared)
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            Task {
                await NotificationManager.reschedule()
                await AnalysisService.shared.prefetchUpcoming(days: 3)
                // 预取完再排一次，让通知正文带上导读
                await NotificationManager.reschedule()
            }
            BackgroundTasks.schedule()
        }
    }
}

/// 点通知后要打开的作品
@Observable
@MainActor
final class Router {
    static let shared = Router()
    var presentedPoem: Poem?
    var selectedTab: RootView.Tab = .today
}

final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        BackgroundTasks.register()
        Task { @MainActor in NotificationManager.registerCategories() }
        return true
    }

    // App 在前台时也展示横幅
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async
        -> UNNotificationPresentationOptions {
        [.banner, .list, .sound]
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        let info = response.notification.request.content.userInfo
        guard let id = (info[NotificationManager.poemIDKey] as? NSNumber)?.int64Value else { return }
        if response.actionIdentifier == "FAVORITE" {
            await MainActor.run { FavoritesStore.shared.add(id) }
            return
        }
        guard let poem = PoetryDatabase.shared.poem(id: id) else { return }
        await MainActor.run {
            Router.shared.selectedTab = .today
            Router.shared.presentedPoem = poem
        }
    }
}
