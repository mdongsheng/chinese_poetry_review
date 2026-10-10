import SwiftUI

/// 作品详情：正文 + 解析（导读、译文、注释、赏析、背景、体裁）+ 作者小传
struct PoemDetailView: View {
    let poem: Poem

    @Environment(FavoritesStore.self) private var favorites
    @AppStorage(SettingsKey.verticalLayout) private var vertical = false
    @AppStorage(SettingsKey.fontScale) private var fontScale = 1.0
    @State private var analysis: Analysis?
    @State private var loading = false
    @State private var error: String?
    @State private var author: Author?
    @State private var section: AnalysisSection = .translation
    @State private var authorExpanded = false

    enum AnalysisSection: String, CaseIterable, Identifiable {
        case translation = "译文", annotations = "注释", appreciation = "赏析", background = "背景", form = "体裁"
        var id: String { rawValue }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 32) {
                PoemTextView(poem: poem, vertical: vertical, scale: fontScale)
                    .padding(.top, 24)
                    .padding(.horizontal, vertical ? 0 : 24)

                if !poem.tags.isEmpty {
                    tagRow
                }

                OrnamentDivider()

                analysisBlock
                    .padding(.horizontal, 24)

                if let prologue = poem.prologue {
                    card("题解", prologue)
                }
                if !poem.notes.isEmpty {
                    card("原注", poem.notes.joined(separator: "\n"))
                }
                if let author, !author.description.isEmpty {
                    // 原数据里多个来源的小传以「--」相连，拆成段落；长的先折叠
                    card("作者 · \(author.name)", author.description.replacingOccurrences(of: "--", with: "\n"),
                         expanded: $authorExpanded)
                }
                VStack(spacing: 14) {
                    if !["佚名", "无名氏", "不详"].contains(poem.author) {
                        moreLink("\(poem.author)的全部作品", Route.author(poem.author))
                    }
                    if let rhythmic = poem.rhythmic {
                        moreLink("更多「\(rhythmic)」", Route.rhythmic(rhythmic))
                    }
                }
            }
            .padding(.bottom, 48)
        }
        .paperBackground()
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { toolbar }
        .task(id: poem.id) {
            author = PoetryDatabase.shared.author(named: poem.author, dynasty: poem.dynasty)
            analysis = AnalysisService.cached(poem.id)
            if analysis == nil && AnalysisService.isConfigured { await load() }
        }
    }

    // MARK: - 解析

    @ViewBuilder
    private var analysisBlock: some View {
        if let analysis {
            VStack(alignment: .leading, spacing: 20) {
                Text(analysis.summary)
                    .font(Theme.poem(17))
                    .foregroundStyle(Theme.ink)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .multilineTextAlignment(.center)

                Picker("解析", selection: $section) {
                    ForEach(AnalysisSection.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)

                Group {
                    switch section {
                    case .translation: paragraphs(analysis.translation)
                    case .annotations: annotations(analysis.annotations)
                    case .appreciation: paragraphs(analysis.appreciation)
                    case .background: paragraphs(analysis.background)
                    case .form: paragraphs(analysis.formIntro)
                    }
                }
                .textSelection(.enabled)
                .animation(.easeInOut(duration: 0.2), value: section)

                if let model = analysis.model {
                    Text("解析由 \(model) 生成，仅供参考")
                        .font(.caption2)
                        .foregroundStyle(Theme.inkFaint)
                }
            }
        } else if loading {
            VStack(spacing: 12) {
                ProgressView()
                Text("正在研墨，生成解析…").font(Theme.poem(14)).foregroundStyle(Theme.inkLight)
            }
            .padding(.vertical, 24)
        } else if !AnalysisService.isConfigured {
            VStack(spacing: 10) {
                Text("在「设置」中填写 Claude 或 DeepSeek 的 API Key 后，即可为每首作品生成译文、注释与赏析。")
                    .font(Theme.body(14))
                    .foregroundStyle(Theme.inkLight)
                    .multilineTextAlignment(.center)
            }
        } else {
            VStack(spacing: 12) {
                if let error {
                    Text(error).font(Theme.body(14)).foregroundStyle(Theme.inkLight).multilineTextAlignment(.center)
                }
                Button("生成解析") { Task { await load() } }
                    .font(Theme.poem(15))
                    .foregroundStyle(Theme.cinnabar)
            }
        }
    }

    private func load(force: Bool = false) async {
        loading = true
        error = nil
        defer { loading = false }
        do {
            analysis = try await AnalysisService.shared.analysis(for: poem, forceRefresh: force)
            if poem.inDailyRotation {
                // 若是即将推送的作品，让通知正文用上新的导读
                await NotificationManager.reschedule()
            }
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func paragraphs(_ text: String) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            ForEach(Array(text.components(separatedBy: "\n").filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }.enumerated()),
                    id: \.offset) { _, p in
                Text(p)
                    .font(Theme.body(16))
                    .foregroundStyle(Theme.ink)
                    .lineSpacing(7)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private func annotations(_ items: [Analysis.Annotation]) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                (Text(item.term).foregroundColor(Theme.cinnabar) + Text("：" + item.explanation))
                    .font(Theme.body(15))
                    .foregroundStyle(Theme.ink)
                    .lineSpacing(5)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    // MARK: - 其它

    private var tagRow: some View {
        HStack(spacing: 8) {
            ForEach(([poem.collection] + poem.tags).prefix(4), id: \.self) { tag in
                Text(tag)
                    .font(Theme.poem(12))
                    .foregroundStyle(Theme.inkLight)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .overlay(RoundedRectangle(cornerRadius: 2).stroke(Theme.inkFaint, lineWidth: 0.5))
            }
        }
    }

    private func moreLink(_ title: String, _ route: Route) -> some View {
        NavigationLink(value: route) {
            HStack {
                Text(title)
                Image(systemName: "chevron.right").font(.caption)
            }
            .font(Theme.poem(15))
            .foregroundStyle(Theme.cinnabar)
        }
    }

    /// 折叠时大约显示的字数；超过才出现「展开全部」
    private static let collapsedLength = 150

    /// 信息卡片。传入 expanded 时，长文先折叠成几行，点「展开全部」显示全文
    private func card(_ title: String, _ text: String, expanded: Binding<Bool>? = nil) -> some View {
        let paragraphs = text.components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        let collapsible = expanded != nil && paragraphs.joined().count > Self.collapsedLength
        let collapsed = collapsible && !(expanded?.wrappedValue ?? true)
        return VStack(alignment: .leading, spacing: 10) {
            Text(title).font(Theme.title(16)).foregroundStyle(Theme.ink)
            if collapsed {
                Text(paragraphs.joined(separator: " "))
                    .font(Theme.body(15))
                    .foregroundStyle(Theme.inkLight)
                    .lineSpacing(6)
                    .lineLimit(5)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                ForEach(Array(paragraphs.enumerated()), id: \.offset) { _, paragraph in
                    Text(paragraph)
                        .font(Theme.body(15))
                        .foregroundStyle(Theme.inkLight)
                        .lineSpacing(6)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            if collapsible, let expanded {
                Button {
                    withAnimation(.easeInOut(duration: 0.25)) { expanded.wrappedValue.toggle() }
                } label: {
                    HStack(spacing: 4) {
                        Text(expanded.wrappedValue ? "收起" : "展开全部")
                        Image(systemName: expanded.wrappedValue ? "chevron.up" : "chevron.down").font(.caption)
                    }
                    .font(Theme.poem(14))
                    .foregroundStyle(Theme.cinnabar)
                    .frame(maxWidth: .infinity)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .textSelection(.enabled)
        .padding(18)
        .background(Theme.paperDeep.opacity(0.6), in: RoundedRectangle(cornerRadius: 4))
        .padding(.horizontal, 20)
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItemGroup(placement: .topBarTrailing) {
            Button {
                vertical.toggle()
            } label: {
                Image(systemName: vertical ? "text.alignleft" : "text.justify.leading")
                    .rotationEffect(.degrees(vertical ? 0 : 90))
            }
            Button {
                favorites.toggle(poem.id)
            } label: {
                Image(systemName: favorites.contains(poem.id) ? "bookmark.fill" : "bookmark")
            }
            Menu {
                ShareLink(item: PoemCard(poem: poem, summary: analysis?.summary),
                          preview: SharePreview(poem.title)) {
                    Label("分享卡片", systemImage: "photo")
                }
                Button {
                    UIPasteboard.general.string = "《\(poem.title)》\(poem.byline)\n\(poem.fullText)"
                } label: {
                    Label("复制原文", systemImage: "doc.on.doc")
                }
                if AnalysisService.isConfigured {
                    Button {
                        Task { await load(force: true) }
                    } label: {
                        Label("重新生成解析", systemImage: "arrow.clockwise")
                    }
                }
            } label: {
                Image(systemName: "ellipsis")
            }
        }
    }
}
