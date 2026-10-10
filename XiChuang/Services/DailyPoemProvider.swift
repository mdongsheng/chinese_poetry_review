import Foundation

/// 把日期映射到「今日一词」。
///
/// 以首次启动那天为第 0 天，按数据库里的 daily_rank 依次往后推，
/// 名篇（宋词三百首、南唐二主词、纳兰词）排在最前面，约 21,800 首词轮完才会重复。
enum DailyPoemProvider {
    static var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = .current
        return c
    }

    static var anchorDate: Date {
        let defaults = AppSettings.defaults
        if let saved = defaults.object(forKey: SettingsKey.anchorDate) as? Date {
            return saved
        }
        let today = calendar.startOfDay(for: .now)
        defaults.set(today, forKey: SettingsKey.anchorDate)
        return today
    }

    static func dayIndex(for date: Date) -> Int {
        let start = calendar.startOfDay(for: anchorDate)
        let day = calendar.startOfDay(for: date)
        return calendar.dateComponents([.day], from: start, to: day).day ?? 0
    }

    static func poem(for date: Date) -> Poem? {
        PoetryDatabase.shared.dailyPoem(rank: dayIndex(for: date))
    }

    /// 从今天开始的连续 n 天，(日期, 词)
    static func upcoming(days n: Int, from date: Date = .now) -> [(date: Date, poem: Poem)] {
        (0..<n).compactMap { offset in
            guard let d = calendar.date(byAdding: .day, value: offset, to: calendar.startOfDay(for: date)),
                  let p = poem(for: d) else { return nil }
            return (d, p)
        }
    }
}
