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
                    NavigationLink(value: Route.author(author.name)) {
                        card("作者 · \(author.name)", author.description, lineLimit: 8, showsChevron: true)
                    }
                    .buttonStyle(.plain)
                }
                if let rhythmic = poem.rhythmic {
                    NavigationLink(value: Route.rhythmic(rhythmic)) {
                        HStack {
                            Text("更多「\(rhythmic)」")
                            Image(systemName: "chevron.right").font(.caption)
                        }
                        .font(Theme.poem(15))
                        .foregroundStyle(Theme.cinnabar)
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

    private func card(_ title: String, _ text: String, lineLimit: Int? = nil, showsChevron: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(title).font(Theme.title(16)).foregroundStyle(Theme.ink)
                Spacer()
                if showsChevron {
                    Image(systemName: "chevron.right").font(.caption).foregroundStyle(Theme.inkFaint)
                }
            }
            Text(text)
                .font(Theme.body(15))
                .foregroundStyle(Theme.inkLight)
                .lineSpacing(6)
                .lineLimit(lineLimit)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
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
