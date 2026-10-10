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
    @AppStorage(SettingsKey.analysisProvider) private var providerRaw = AnalysisProvider.claude.rawValue
    @AppStorage(SettingsKey.deepSeekModel) private var deepSeekModel = AnalysisProvider.defaultDeepSeekModel

    @State private var apiKey = KeychainHelper.apiKey(for: AppSettings.provider) ?? ""
    @State private var deepSeekModels: [String] = []
    @State private var modelsError: String?
    @State private var loadingModels = false
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
                    Picker("服务", selection: $providerRaw) {
                        ForEach(AnalysisProvider.allCases) { Text($0.displayName).tag($0.rawValue) }
                    }
                    SecureField(provider.keyPlaceholder, text: $apiKey)
                        .textContentType(.password)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .onSubmit { saveKey() }
                    switch provider {
                    case .claude:
                        Picker("模型", selection: $model) {
                            ForEach(ClaudeModel.allCases) { Text($0.displayName).tag($0.rawValue) }
                        }
                    case .deepseek:
                        deepSeekModelRows
                    }
                    Link("申请 \(provider.displayName) API Key", destination: provider.consoleURL)
                } header: {
                    Text("解析")
                } footer: {
                    Text("译文、注释、赏析由所选服务生成，结果缓存在本机，同一首只生成一次，换服务后已生成的解析照常显示。各家的 API Key 分别保存在钥匙串中，只用于直接请求该服务的官方接口（api.anthropic.com / api.deepseek.com）。")
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
            .onChange(of: providerRaw) { _, _ in
                // 换服务时输入框显示该服务自己的 Key
                apiKey = KeychainHelper.apiKey(for: provider) ?? ""
                deepSeekModels = []
                modelsError = nil
                Task { await AnalysisService.shared.prefetchUpcoming(days: 3) }
            }
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

    private var provider: AnalysisProvider { AnalysisProvider(rawValue: providerRaw) ?? .claude }

    /// DeepSeek 的模型名常有变动：可手填，也可以用 Key 拉取当前可用的模型
    @ViewBuilder
    private var deepSeekModelRows: some View {
        LabeledContent("模型") {
            TextField(AnalysisProvider.defaultDeepSeekModel, text: $deepSeekModel)
                .multilineTextAlignment(.trailing)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
        }
        if deepSeekModels.isEmpty {
            Button(loadingModels ? "正在获取…" : "获取可用模型") {
                Task { await loadDeepSeekModels() }
            }
            .disabled(apiKey.isEmpty || loadingModels)
        } else {
            Picker("可用模型", selection: $deepSeekModel) {
                ForEach(deepSeekModels, id: \.self) { Text($0).tag($0) }
                if !deepSeekModels.contains(deepSeekModel) {
                    Text(deepSeekModel).tag(deepSeekModel)
                }
            }
        }
        if let modelsError {
            Text(modelsError).font(.footnote).foregroundStyle(Theme.cinnabar)
        }
    }

    private func loadDeepSeekModels() async {
        loadingModels = true
        modelsError = nil
        defer { loadingModels = false }
        do {
            deepSeekModels = try await AnalysisService.deepSeekModels(apiKey: apiKey.trimmingCharacters(in: .whitespacesAndNewlines))
            if deepSeekModels.isEmpty { modelsError = "这个 Key 没有可用的模型。" }
        } catch {
            modelsError = error.localizedDescription
        }
    }

    private func saveKey() {
        KeychainHelper.setAPIKey(apiKey.trimmingCharacters(in: .whitespacesAndNewlines), for: provider)
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
