import Foundation

/// 存在 UserDefaults 里的偏好设置的键与默认值。视图里用 @AppStorage 读写同一组键。
enum SettingsKey {
    static let pushEnabled = "pushEnabled"
    static let pushHour = "pushHour"
    static let pushMinute = "pushMinute"
    static let verticalLayout = "verticalLayout"
    static let fontScale = "fontScale"
    static let claudeModel = "claudeModel"
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
        ])
    }

    static var pushEnabled: Bool { defaults.bool(forKey: SettingsKey.pushEnabled) }
    static var pushHour: Int { defaults.integer(forKey: SettingsKey.pushHour) }
    static var pushMinute: Int { defaults.integer(forKey: SettingsKey.pushMinute) }
    static var model: ClaudeModel {
        ClaudeModel(rawValue: defaults.string(forKey: SettingsKey.claudeModel) ?? "") ?? .opus
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
