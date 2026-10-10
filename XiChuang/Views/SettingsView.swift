import SwiftUI
import UserNotifications

struct SettingsView: View {
    @AppStorage(SettingsKey.pushEnabled) private var pushEnabled = true
    @AppStorage(SettingsKey.pushHour) private var pushHour = 8
    @AppStorage(SettingsKey.pushMinute) private var pushMinute = 0
    @AppStorage(SettingsKey.verticalLayout) private var vertical = false
    @AppStorage(SettingsKey.fontScale) private var fontScale = 1.0
    @AppStorage(SettingsKey.claudeModel) private var model = ClaudeModel.opus.rawValue
    @AppStorage(SettingsKey.dailyContent) private var dailyContent = DailyContent.alternate.rawValue

    @State private var apiKey = KeychainHelper.apiKey ?? ""
    @State private var authStatus: UNAuthorizationStatus = .notDetermined
    @State private var testSent = false

    private var pushTime: Binding<Date> {
        Binding {
            DailyPoemProvider.calendar.date(bySettingHour: pushHour, minute: pushMinute, second: 0, of: .now) ?? .now
        } set: { date in
            let c = DailyPoemProvider.calendar.dateComponents([.hour, .minute], from: date)
            pushHour = c.hour ?? 8
            pushMinute = c.minute ?? 0
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle("每日推送", isOn: $pushEnabled)
                    if pushEnabled {
                        DatePicker("推送时间", selection: pushTime, displayedComponents: .hourAndMinute)
                    }
                    Picker("推送内容", selection: $dailyContent) {
                        ForEach(DailyContent.allCases) { Text($0.displayName).tag($0.rawValue) }
                    }
                    if authStatus == .denied {
                        Button("通知权限已关闭，去系统设置开启") {
                            if let url = URL(string: UIApplication.openNotificationSettingsURLString) {
                                UIApplication.shared.open(url)
                            }
                        }
                        .foregroundStyle(Theme.cinnabar)
                    }
                    Button(testSent ? "已发送，5 秒后到达" : "发送一条试推") {
                        Task {
                            if await NotificationManager.requestAuthorization() {
                                await NotificationManager.sendTest()
                                testSent = true
                            }
                            await refreshAuth()
                        }
                    }
                } header: {
                    Text("推送")
                } footer: {
                    Text("诗词交替：一天词、一天律诗（五律、七律）。推送使用本机定时通知，无需联网也会准时到达。若已填写 API Key，App 会提前生成解析，通知里会附上一句导读。")
                }

                Section {
                    SecureField("sk-ant-…", text: $apiKey)
                        .textContentType(.password)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .onSubmit { saveKey() }
                    Picker("模型", selection: $model) {
                        ForEach(ClaudeModel.allCases) { Text($0.displayName).tag($0.rawValue) }
                    }
                } header: {
                    Text("解析（Claude）")
                } footer: {
                    Text("译文、注释、赏析由 Claude 生成，结果缓存在本机，同一首只生成一次。API Key 保存在钥匙串中，仅用于直接请求 api.anthropic.com。可在 console.anthropic.com 申请。")
                }

                Section("阅读") {
                    Toggle("竖排显示", isOn: $vertical)
                    VStack(alignment: .leading) {
                        Text("字号")
                        Slider(value: $fontScale, in: 0.8...1.4, step: 0.1) {
                            Text("字号")
                        } minimumValueLabel: {
                            Text("小").font(.caption)
                        } maximumValueLabel: {
                            Text("大").font(.title3)
                        }
                    }
                }

                Section("关于") {
                    LabeledContent("收录作品", value: "\(PoetryDatabase.shared.totalCount) 首")
                    LabeledContent("推送轮换", value: "词 \(PoetryDatabase.shared.dailyCiCount) 首 · 律诗 \(PoetryDatabase.shared.dailyShiCount) 首")
                    Link("数据来源：chinese-poetry", destination: URL(string: "https://github.com/chinese-poetry/chinese-poetry")!)
                }
            }
            .scrollContentBackground(.hidden)
            .paperBackground()
            .navigationTitle("设置")
            .onChange(of: apiKey) { _, _ in saveKey() }
            .onChange(of: pushEnabled) { _, on in
                Task {
                    if on { _ = await NotificationManager.requestAuthorization() }
                    await NotificationManager.reschedule()
                    await refreshAuth()
                }
            }
            .onChange(of: pushHour) { _, _ in reschedule() }
            .onChange(of: pushMinute) { _, _ in reschedule() }
            .onChange(of: dailyContent) { _, _ in
                reschedule()
                Task { await AnalysisService.shared.prefetchUpcoming(days: 3) }
            }
            .task { await refreshAuth() }
        }
    }

    private func saveKey() {
        KeychainHelper.apiKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func reschedule() {
        Task {
            await NotificationManager.reschedule()
            BackgroundTasks.schedule()
        }
    }

    private func refreshAuth() async {
        authStatus = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
    }
}
