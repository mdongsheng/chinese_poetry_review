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
        ])
    }

    static var pushEnabled: Bool { defaults.bool(forKey: SettingsKey.pushEnabled) }
    static var pushHour: Int { defaults.integer(forKey: SettingsKey.pushHour) }
    static var pushMinute: Int { defaults.integer(forKey: SettingsKey.pushMinute) }
    static var dailyContent: DailyContent {
        DailyContent(rawValue: defaults.string(forKey: SettingsKey.dailyContent) ?? "") ?? .alternate
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
