import Foundation

/// 把日期映射到当天推送的作品。
///
/// 以首次启动那天为第 0 天。默认「诗词交替」：第 0、2、4… 天推词，第 1、3、5… 天推律诗，
/// 各自按数据库里的 daily_ci_rank / daily_shi_rank 依次往后走。
/// 两个序列都是名篇在前：词以宋词三百首、南唐二主词、纳兰词开头，律诗以唐诗三百首开头。
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
        let day = dayIndex(for: date)
        let db = PoetryDatabase.shared
        switch AppSettings.dailyContent {
        case .ci:
            return db.dailyPoem(kind: .ci, rank: day)
        case .lushi:
            return db.dailyPoem(kind: .shi, rank: day)
        case .alternate:
            return db.dailyPoem(kind: day % 2 == 0 ? .ci : .shi, rank: day / 2)
        }
    }

    /// 从今天开始的连续 n 天，(日期, 作品)
    static func upcoming(days n: Int, from date: Date = .now) -> [(date: Date, poem: Poem)] {
        (0..<n).compactMap { offset in
            guard let d = calendar.date(byAdding: .day, value: offset, to: calendar.startOfDay(for: date)),
                  let p = poem(for: d) else { return nil }
            return (d, p)
        }
    }
}
