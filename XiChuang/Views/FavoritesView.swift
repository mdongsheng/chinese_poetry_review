import SwiftUI

struct FavoritesView: View {
    @Environment(FavoritesStore.self) private var favorites

    var body: some View {
        NavigationStack {
            Group {
                if favorites.ids.isEmpty {
                    ContentUnavailableView("尚无收藏", systemImage: "bookmark",
                                           description: Text("读到喜欢的词，点书签即可收藏。"))
                } else {
                    List {
                        ForEach(favorites.ids.compactMap { PoetryDatabase.shared.poem(id: $0) }) { poem in
                            PoemRow(poem: poem)
                                .swipeActions {
                                    Button("取消收藏", role: .destructive) { favorites.toggle(poem.id) }
                                }
                        }
                        .listRowBackground(Theme.paperDeep.opacity(0.5))
                    }
                    .scrollContentBackground(.hidden)
                }
            }
            .paperBackground()
            .navigationTitle("收藏")
            .appRoutes()
        }
    }
}
