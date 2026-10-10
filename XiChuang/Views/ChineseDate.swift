import Foundation

/// 农历日期文字，例如「丙午年 八月廿九」
enum ChineseDate {
    private static let stems = Array("甲乙丙丁戊己庚辛壬癸")
    private static let branches = Array("子丑寅卯辰巳午未申酉戌亥")
    private static let months = ["正", "二", "三", "四", "五", "六", "七", "八", "九", "十", "冬", "腊"]
    private static let dayPrefix = ["初", "十", "廿", "三"]
    private static let digits = ["十", "一", "二", "三", "四", "五", "六", "七", "八", "九"]

    static func lunar(_ date: Date) -> String {
        let cal = Calendar(identifier: .chinese)
        let c = cal.dateComponents([.year, .month, .day], from: date)
        let isLeap = cal.dateComponents(in: .current, from: date).isLeapMonth ?? false
        guard let y = c.year, let m = c.month, let d = c.day else { return "" }
        let ganzhi = "\(stems[(y - 1) % 10])\(branches[(y - 1) % 12])"
        return "\(ganzhi)年 \(isLeap ? "闰" : "")\(months[(m - 1) % 12])月\(dayName(d))"
    }

    private static func dayName(_ d: Int) -> String {
        switch d {
        case 10: "初十"
        case 20: "二十"
        case 30: "三十"
        default: dayPrefix[d / 10] + digits[d % 10]
        }
    }

    static func weekday(_ date: Date) -> String {
        let names = ["日", "一", "二", "三", "四", "五", "六"]
        let w = Calendar(identifier: .gregorian).component(.weekday, from: date)
        return "星期" + names[w - 1]
    }
}
