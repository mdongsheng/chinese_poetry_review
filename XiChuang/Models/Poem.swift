import Foundation

/// 一首作品（诗 / 词 / 曲），对应数据库 poems 表的一行。
struct Poem: Identifiable, Hashable, Sendable {
    enum Kind: String, Sendable {
        case ci, shi, qu

        var label: String {
            switch self {
            case .ci: "词"
            case .shi: "诗"
            case .qu: "曲"
            }
        }
    }

    let id: Int64
    let title: String
    let author: String
    let dynasty: String
    let collection: String
    let kind: Kind
    let rhythmic: String?
    let lines: [String]
    let notes: [String]
    let prologue: String?
    let tags: [String]
    let dailyRank: Int?

    var fullText: String { lines.joined(separator: "\n") }

    /// 「〔宋〕苏轼」
    var byline: String { "〔\(dynasty)〕\(author)" }

    /// 通知、列表里用的前两句
    var excerpt: String {
        lines.prefix(2).joined()
    }
}

struct Author: Hashable, Sendable {
    let name: String
    let dynasty: String
    let description: String
}
