import SwiftUI

/// 「发现」：搜索、按合集 / 词牌 / 词人浏览、随机一首
struct DiscoverView: View {
    @State private var query = ""
    @State private var results: [Poem] = []
    @State private var searching = false
    @State private var path: [Route] = []

    private let collections: [(name: String, subtitle: String, tag: String?)] = [
        ("宋词", "宋词三百首", "宋词三百首"),
        ("宋词", "全宋词", nil),
        ("南唐二主词", "李璟 · 李煜", nil),
        ("花间集", "温庭筠 · 韦庄 等", nil),
        ("纳兰词", "纳兰性德", nil),
        ("全唐诗", "唐诗三百首", "唐诗三百首"),
        ("全唐诗", "全唐诗", nil),
        ("宋诗", "全宋诗", nil),
        ("元曲", "关汉卿 · 马致远 等", nil),
        ("诗经", "风 · 雅 · 颂", nil),
        ("楚辞", "屈原 · 宋玉 等", nil),
        ("曹操诗集", "建安风骨", nil),
    ]

    var body: some View {
        NavigationStack(path: $path) {
            List {
                if !query.isEmpty {
                    searchResults
                } else {
                    browse
                }
            }
            .scrollContentBackground(.hidden)
            .listStyle(.insetGrouped)
            .paperBackground()
            .navigationTitle("发现")
            .searchable(text: $query, prompt: "题目、作者、名句")
            .task(id: query) { await search() }
            .appRoutes()
        }
    }

    @ViewBuilder
    private var searchResults: some View {
        if searching && results.isEmpty {
            HStack { Spacer(); ProgressView(); Spacer() }.listRowBackground(Color.clear)
        } else if results.isEmpty {
            Text("未找到「\(query)」").foregroundStyle(Theme.inkLight).listRowBackground(Color.clear)
        } else {
            ForEach(results) { PoemRow(poem: $0) }
                .listRowBackground(Theme.paperDeep.opacity(0.5))
        }
    }

    @ViewBuilder
    private var browse: some View {
        Section {
            Button {
                if let p = PoetryDatabase.shared.randomPoem(kind: .ci) { path.append(.poem(p)) }
            } label: {
                Label("随机一首词", systemImage: "dice")
            }
            Button {
                if let p = PoetryDatabase.shared.randomLushi() { path.append(.poem(p)) }
            } label: {
                Label("随机一首律诗", systemImage: "shuffle")
            }
        }
        .font(Theme.poem(16))
        .foregroundStyle(Theme.cinnabar)
        .listRowBackground(Theme.paperDeep.opacity(0.5))

        Section("合集") {
            ForEach(collections, id: \.subtitle) { c in
                NavigationLink(value: Route.collection(name: c.name, title: c.subtitle, tag: c.tag)) {
                    HStack {
                        Text(c.subtitle).font(Theme.poem(17)).foregroundStyle(Theme.ink)
                        Spacer()
                        Text(c.tag == nil ? c.name : "").font(Theme.poem(13)).foregroundStyle(Theme.inkLight)
                    }
                }
            }
        }
        .listRowBackground(Theme.paperDeep.opacity(0.5))

        Section("词牌") {
            NavigationLink("常见词牌", value: Route.rhythmicList)
        }
        .font(Theme.poem(17))
        .listRowBackground(Theme.paperDeep.opacity(0.5))

        Section("词人") {
            NavigationLink("宋词名家", value: Route.authorList)
        }
        .font(Theme.poem(17))
        .listRowBackground(Theme.paperDeep.opacity(0.5))
    }

    private func search() async {
        let q = query
        guard !q.trimmingCharacters(in: .whitespaces).isEmpty else { results = []; return }
        // 简单防抖
        try? await Task.sleep(for: .milliseconds(300))
        guard !Task.isCancelled else { return }
        searching = true
        let found = await Task.detached(priority: .userInitiated) {
            PoetryDatabase.shared.search(q)
        }.value
        guard !Task.isCancelled else { return }
        results = found
        searching = false
    }
}

struct PoemRow: View {
    let poem: Poem

    var body: some View {
        NavigationLink(value: Route.poem(poem)) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline) {
                    Text(poem.title).font(Theme.title(17)).foregroundStyle(Theme.ink).lineLimit(1)
                    Spacer()
                    Text(poem.byline).font(Theme.poem(13)).foregroundStyle(Theme.inkLight).lineLimit(1)
                }
                Text(poem.excerpt)
                    .font(Theme.poem(14))
                    .foregroundStyle(Theme.inkLight)
                    .lineLimit(1)
            }
            .padding(.vertical, 4)
        }
    }
}

struct PoemListView: View {
    let title: String
    let poems: [Poem]

    var body: some View {
        List(poems) { PoemRow(poem: $0) }
            .listRowBackground(Theme.paperDeep.opacity(0.5))
            .scrollContentBackground(.hidden)
            .paperBackground()
            .navigationTitle(title)
    }
}

/// 合集分页浏览（全宋诗有二十多万首，按需加载）
struct CollectionView: View {
    let collection: String
    let title: String
    let tag: String?
    @State private var poems: [Poem] = []
    @State private var exhausted = false

    var body: some View {
        List {
            ForEach(poems) { poem in
                PoemRow(poem: poem)
                    .onAppear { if poem.id == poems.last?.id { loadMore() } }
            }
            .listRowBackground(Theme.paperDeep.opacity(0.5))
        }
        .scrollContentBackground(.hidden)
        .paperBackground()
        .navigationTitle(title)
        .onAppear { if poems.isEmpty { loadMore() } }
    }

    private func loadMore() {
        guard !exhausted else { return }
        let page = PoetryDatabase.shared.poems(inCollection: collection, tag: tag, offset: poems.count, limit: 80)
        exhausted = page.count < 80
        poems += page
    }
}

struct RhythmicListView: View {
    @State private var items: [(name: String, count: Int)] = []

    var body: some View {
        List(items, id: \.name) { item in
            NavigationLink(value: Route.rhythmic(item.name)) {
                HStack {
                    Text(item.name).font(Theme.poem(17))
                    Spacer()
                    Text("\(item.count) 首").font(Theme.poem(13)).foregroundStyle(Theme.inkLight)
                }
            }
            .listRowBackground(Theme.paperDeep.opacity(0.5))
        }
        .scrollContentBackground(.hidden)
        .paperBackground()
        .navigationTitle("词牌")
        .task { if items.isEmpty { items = PoetryDatabase.shared.topRhythmics() } }
    }
}

struct CiAuthorListView: View {
    @State private var items: [(name: String, count: Int)] = []

    var body: some View {
        List(items, id: \.name) { item in
            NavigationLink(value: Route.author(item.name)) {
                HStack {
                    Text(item.name).font(Theme.poem(17))
                    Spacer()
                    Text("\(item.count) 首").font(Theme.poem(13)).foregroundStyle(Theme.inkLight)
                }
            }
            .listRowBackground(Theme.paperDeep.opacity(0.5))
        }
        .scrollContentBackground(.hidden)
        .paperBackground()
        .navigationTitle("词人")
        .task { if items.isEmpty { items = PoetryDatabase.shared.topCiAuthors() } }
    }
}
