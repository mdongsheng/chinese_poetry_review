import SwiftUI

struct RootView: View {
    enum Tab: Hashable { case today, discover, favorites, settings }

    @Environment(Router.self) private var router

    var body: some View {
        @Bindable var router = router
        Group {
            if PoetryDatabase.shared.isAvailable {
                TabView(selection: $router.selectedTab) {
                    TodayView()
                        .tabItem { Label("今日", systemImage: "sun.haze") }
                        .tag(Tab.today)
                    DiscoverView()
                        .tabItem { Label("发现", systemImage: "books.vertical") }
                        .tag(Tab.discover)
                    FavoritesView()
                        .tabItem { Label("收藏", systemImage: "bookmark") }
                        .tag(Tab.favorites)
                    SettingsView()
                        .tabItem { Label("设置", systemImage: "gearshape") }
                        .tag(Tab.settings)
                }
                .tint(Theme.cinnabar)
                .sheet(item: $router.presentedPoem) { poem in
                    NavigationStack {
                        PoemDetailView(poem: poem)
                            .navigationDestination(for: Poem.self) { PoemDetailView(poem: $0) }
                            .toolbar {
                                ToolbarItem(placement: .cancellationAction) {
                                    Button("关闭") { router.presentedPoem = nil }
                                }
                            }
                    }
                    .tint(Theme.cinnabar)
                }
            } else {
                ContentUnavailableView("缺少诗词库",
                                       systemImage: "exclamationmark.triangle",
                                       description: Text("请先运行 scripts/bootstrap.sh 生成 poetry.sqlite，再重新编译。"))
                    .paperBackground()
            }
        }
        .task { await requestNotificationPermissionOnce() }
    }

    private func requestNotificationPermissionOnce() async {
        let key = "askedNotificationPermission"
        guard !UserDefaults.standard.bool(forKey: key) else { return }
        UserDefaults.standard.set(true, forKey: key)
        if await NotificationManager.requestAuthorization() {
            await NotificationManager.reschedule()
        }
    }
}
