import Foundation
import Observation

/// 收藏夹，按收藏时间倒序保存作品 id。
@Observable
final class FavoritesStore {
    static let shared = FavoritesStore()

    private static let key = "favoritePoemIDs"
    private(set) var ids: [Int64]

    private init() {
        ids = (UserDefaults.standard.array(forKey: Self.key) as? [NSNumber])?.map(\.int64Value) ?? []
    }

    func contains(_ id: Int64) -> Bool { ids.contains(id) }

    func toggle(_ id: Int64) {
        if let i = ids.firstIndex(of: id) {
            ids.remove(at: i)
        } else {
            ids.insert(id, at: 0)
        }
        save()
    }

    func add(_ id: Int64) {
        guard !contains(id) else { return }
        ids.insert(id, at: 0)
        save()
    }

    private func save() {
        UserDefaults.standard.set(ids.map { NSNumber(value: $0) }, forKey: Self.key)
    }
}
