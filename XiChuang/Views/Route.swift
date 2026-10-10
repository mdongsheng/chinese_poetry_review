import SwiftUI

/// App 内所有页面跳转。
///
/// 每个 NavigationStack 都只用 NavigationLink(value:) 加这里统一注册的 navigationDestination。
/// 不要再混用 NavigationLink { 目标页面 }：两种写法混在一个栈里，
/// 点进作品时页面会压进栈却不显示，返回时才一层层冒出来。
enum Route: Hashable {
    case poem(Poem)
    case author(String)
    case rhythmic(String)
    case collection(name: String, title: String, tag: String?)
    case rhythmicList
    case authorList

    @MainActor @ViewBuilder
    var destination: some View {
        switch self {
        case .poem(let poem):
            PoemDetailView(poem: poem)
        case .author(let name):
            PoemListView(title: name, poems: PoetryDatabase.shared.poems(byAuthor: name))
        case .rhythmic(let name):
            PoemListView(title: name, poems: PoetryDatabase.shared.poems(byRhythmic: name))
        case .collection(let name, let title, let tag):
            CollectionView(collection: name, title: title, tag: tag)
        case .rhythmicList:
            RhythmicListView()
        case .authorList:
            CiAuthorListView()
        }
    }
}

extension View {
    /// 挂在 NavigationStack 的根视图上
    func appRoutes() -> some View {
        navigationDestination(for: Route.self) { $0.destination }
    }
}
