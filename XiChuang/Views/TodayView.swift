import SwiftUI

/// 「今日」页：一天一首词或律诗，左右滑动可翻看往日。
struct TodayView: View {
    /// 从首次使用那天起，最多往回翻 30 天；最后一页是今天
    private let dates: [Date]
    @State private var selection: Int

    init() {
        let cal = DailyPoemProvider.calendar
        let today = cal.startOfDay(for: .now)
        let anchor = cal.startOfDay(for: DailyPoemProvider.anchorDate)
        let dates = (0...30).reversed()
            .compactMap { cal.date(byAdding: .day, value: -$0, to: today) }
            .filter { $0 >= anchor }
        self.dates = dates.isEmpty ? [today] : dates
        _selection = State(initialValue: self.dates.count - 1)
    }

    var body: some View {
        NavigationStack {
            TabView(selection: $selection) {
                ForEach(Array(dates.enumerated()), id: \.offset) { i, date in
                    DayPage(date: date).tag(i)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .paperBackground()
            .navigationDestination(for: Poem.self) { PoemDetailView(poem: $0) }
            .toolbar(.hidden, for: .navigationBar)
        }
    }
}

private struct DayPage: View {
    let date: Date
    @Environment(FavoritesStore.self) private var favorites
    @AppStorage(SettingsKey.verticalLayout) private var vertical = false
    @AppStorage(SettingsKey.fontScale) private var fontScale = 1.0
    @State private var analysis: Analysis?

    private var poem: Poem? { DailyPoemProvider.poem(for: date) }
    private var isToday: Bool { Calendar.current.isDateInToday(date) }

    var body: some View {
        ScrollView {
            VStack(spacing: 28) {
                header
                if let poem {
                    NavigationLink(value: poem) {
                        VStack(spacing: 24) {
                            PoemTextView(poem: poem, vertical: vertical, scale: fontScale)
                            if let analysis {
                                Text(analysis.summary)
                                    .font(Theme.body(15))
                                    .foregroundStyle(Theme.inkLight)
                                    .multilineTextAlignment(.center)
                                    .padding(.horizontal, 32)
                            }
                        }
                        .padding(.vertical, 36)
                        .padding(.horizontal, 16)
                        .frame(maxWidth: .infinity)
                        .background(Theme.paper.opacity(0.6), in: RoundedRectangle(cornerRadius: 2))
                        .overlay(RoundedRectangle(cornerRadius: 2).stroke(Theme.inkFaint.opacity(0.4), lineWidth: 0.5))
                        .padding(.horizontal, 18)
                    }
                    .buttonStyle(.plain)

                    actions(poem)
                }
            }
            .padding(.top, 24)
            .padding(.bottom, 40)
        }
        .scrollIndicators(.hidden)
        .task(id: date) { analysis = poem.flatMap { AnalysisService.cached($0.id) } }
    }

    private var header: some View {
        let cal = Calendar(identifier: .gregorian)
        let day = cal.component(.day, from: date)
        let month = cal.component(.month, from: date)
        return HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("\(day)")
                    .font(.system(size: 54, weight: .light, design: .serif))
                    .foregroundStyle(Theme.ink)
                Text("\(month)月 · \(ChineseDate.weekday(date))")
                    .font(Theme.poem(14))
                    .foregroundStyle(Theme.inkLight)
            }
            Rectangle().fill(Theme.inkFaint).frame(width: 0.5, height: 56)
            VStack(alignment: .leading, spacing: 6) {
                Text(ChineseDate.lunar(date))
                    .font(Theme.poem(15))
                    .foregroundStyle(Theme.ink)
                Text("\(isToday ? "今日" : "往日")一\(poem?.kind.label ?? "词")")
                    .font(Theme.poem(13))
                    .foregroundStyle(Theme.inkLight)
            }
            Spacer()
            SealStamp(text: isToday ? "今日" : "往日", size: 40)
        }
        .padding(.horizontal, 28)
    }

    private func actions(_ poem: Poem) -> some View {
        HStack(spacing: 44) {
            Button {
                favorites.toggle(poem.id)
            } label: {
                Image(systemName: favorites.contains(poem.id) ? "bookmark.fill" : "bookmark")
            }
            NavigationLink(value: poem) {
                Text("阅读解析")
                    .font(Theme.poem(15))
                    .padding(.horizontal, 22)
                    .padding(.vertical, 8)
                    .overlay(Capsule().stroke(Theme.cinnabar, lineWidth: 0.8))
            }
            ShareLink(item: PoemCard(poem: poem, summary: analysis?.summary),
                      preview: SharePreview(poem.title)) {
                Image(systemName: "square.and.arrow.up")
            }
        }
        .font(.system(size: 18, weight: .light))
        .foregroundStyle(Theme.cinnabar)
    }
}
