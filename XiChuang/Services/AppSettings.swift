import Foundation

/// 存在 UserDefaults 里的偏好设置的键与默认值。视图里用 @AppStorage 读写同一组键。
enum SettingsKey {
    static let pushEnabled = "pushEnabled"
    static let pushHour = "pushHour"
    static let pushMinute = "pushMinute"
    static let verticalLayout = "verticalLayout"
    static let fontScale = "fontScale"
    static let claudeModel = "claudeModel"
    static let dailyContent = "dailyContent"
    static let analysisProvider = "analysisProvider"
    static let deepSeekModel = "deepSeekModel"
    static let claudeBaseURL = "claudeBaseURL"
    static let deepSeekBaseURL = "deepSeekBaseURL"
    static let anchorDate = "dailyAnchorDate"
}

enum AppSettings {
    static var defaults: UserDefaults { .standard }

    static func registerDefaults() {
        defaults.register(defaults: [
            SettingsKey.pushEnabled: true,
            SettingsKey.pushHour: 8,
            SettingsKey.pushMinute: 0,
            SettingsKey.verticalLayout: false,
            SettingsKey.fontScale: 1.0,
            SettingsKey.claudeModel: ClaudeModel.opus.rawValue,
            SettingsKey.dailyContent: DailyContent.alternate.rawValue,
            SettingsKey.analysisProvider: AnalysisProvider.claude.rawValue,
            SettingsKey.deepSeekModel: AnalysisProvider.defaultDeepSeekModel,
        ])
    }

    static var pushEnabled: Bool { defaults.bool(forKey: SettingsKey.pushEnabled) }
    static var pushHour: Int { defaults.integer(forKey: SettingsKey.pushHour) }
    static var pushMinute: Int { defaults.integer(forKey: SettingsKey.pushMinute) }
    static var dailyContent: DailyContent {
        DailyContent(rawValue: defaults.string(forKey: SettingsKey.dailyContent) ?? "") ?? .alternate
    }

    static var provider: AnalysisProvider {
        AnalysisProvider(rawValue: defaults.string(forKey: SettingsKey.analysisProvider) ?? "") ?? .claude
    }

    /// 自定义的接口地址，留空用官方地址；格式不对时返回 nil
    static func baseURL(for provider: AnalysisProvider) -> URL? {
        let custom = defaults.string(forKey: provider.baseURLKey)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return AnalysisProvider.parseBaseURL(custom.isEmpty ? provider.defaultBaseURL : custom)
    }

    static var deepSeekModel: String {
        let m = defaults.string(forKey: SettingsKey.deepSeekModel)?.trimmingCharacters(in: .whitespaces) ?? ""
        return m.isEmpty ? AnalysisProvider.defaultDeepSeekModel : m
    }

    static var model: ClaudeModel {
        ClaudeModel(rawValue: defaults.string(forKey: SettingsKey.claudeModel) ?? "") ?? .opus
    }
}

/// 每日推送的内容
enum DailyContent: String, CaseIterable, Identifiable {
    case alternate, ci, lushi

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .alternate: "诗词交替"
        case .ci: "只推词"
        case .lushi: "只推律诗"
        }
    }
}

/// 生成解析用的服务
enum AnalysisProvider: String, CaseIterable, Identifiable {
    case claude, deepseek

    /// DeepSeek 的模型名变动频繁，设置页可以从 /models 拉取最新列表替换
    static let defaultDeepSeekModel = "deepseek-v4-pro"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .claude: "Claude（Anthropic）"
        case .deepseek: "DeepSeek"
        }
    }

    /// claude 沿用最早的账户名，升级后不用重填
    var keychainAccount: String {
        switch self {
        case .claude: "anthropic-api-key"
        case .deepseek: "deepseek-api-key"
        }
    }

    var defaultBaseURL: String {
        switch self {
        case .claude: "https://api.anthropic.com"
        case .deepseek: "https://api.deepseek.com"
        }
    }

    var baseURLKey: String {
        switch self {
        case .claude: SettingsKey.claudeBaseURL
        case .deepseek: SettingsKey.deepSeekBaseURL
        }
    }

    /// 只接受 http(s) 且带主机名的地址，去掉末尾的斜杠
    static func parseBaseURL(_ text: String) -> URL? {
        var s = text.trimmingCharacters(in: .whitespacesAndNewlines)
        while s.hasSuffix("/") { s.removeLast() }
        guard let url = URL(string: s), let scheme = url.scheme?.lowercased(),
              scheme == "https" || scheme == "http", url.host() != nil else { return nil }
        return url
    }

    var keyPlaceholder: String {
        switch self {
        case .claude: "sk-ant-…"
        case .deepseek: "sk-…"
        }
    }

    var consoleURL: URL {
        switch self {
        case .claude: URL(string: "https://console.anthropic.com/")!
        case .deepseek: URL(string: "https://platform.deepseek.com/api_keys")!
        }
    }
}

enum ClaudeModel: String, CaseIterable, Identifiable {
    case opus = "claude-opus-5-5"
    case sonnet = "claude-sonnet-5-5"
    case haiku = "claude-haiku-5-5"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .opus: "Claude Opus 5.5（解析最细致）"
        case .sonnet: "Claude Sonnet 5.5（均衡）"
        case .haiku: "Claude Haiku 5.5（最省钱）"
        }
    }

    /// Haiku 没有服务端拒答回退
    var supportsServerFallback: Bool { self != .haiku }
}
