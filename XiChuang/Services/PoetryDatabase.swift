import Foundation
import SQLite3

/// 内置诗词库（只读 SQLite，由 scripts/build_database.py 生成）。
final class PoetryDatabase: @unchecked Sendable {
    static let shared = PoetryDatabase()

    enum DBError: Error { case missing, open(String) }

    private var db: OpaquePointer?
    private let lock = NSLock()

    /// 进入每日推送轮换的词的数量
    private(set) var dailyCount: Int = 0
    private(set) var totalCount: Int = 0
    private(set) var isAvailable = false

    private init() {
        do {
            try open()
            dailyCount = Int(scalar("SELECT COUNT(*) FROM poems WHERE daily_rank IS NOT NULL") ?? 0)
            totalCount = Int(scalar("SELECT COUNT(*) FROM poems") ?? 0)
            isAvailable = true
        } catch {
            print("诗词库打开失败: \(error)")
        }
    }

    private func open() throws {
        guard let url = Bundle.main.url(forResource: "poetry", withExtension: "sqlite") else {
            throw DBError.missing
        }
        let flags = SQLITE_OPEN_READONLY | SQLITE_OPEN_FULLMUTEX
        if sqlite3_open_v2(url.path, &db, flags, nil) != SQLITE_OK {
            throw DBError.open(String(cString: sqlite3_errmsg(db)))
        }
    }

    // MARK: - 查询

    func poem(id: Int64) -> Poem? {
        poems("SELECT \(Self.columns) FROM poems WHERE id = ?", [.int(id)]).first
    }

    /// 每日推送序列中第 rank 首词
    func dailyPoem(rank: Int) -> Poem? {
        guard dailyCount > 0 else { return nil }
        let r = ((rank % dailyCount) + dailyCount) % dailyCount
        return poems("SELECT \(Self.columns) FROM poems WHERE daily_rank = ?", [.int(Int64(r))]).first
    }

    /// 随机一首；只要词时从每日序列里挑，否则按 id 随机跳（比 ORDER BY RANDOM() 快得多）
    func randomPoem(kind: Poem.Kind? = nil) -> Poem? {
        if kind == .ci, dailyCount > 0 {
            return dailyPoem(rank: Int.random(in: 0..<dailyCount))
        }
        let maxID = scalar("SELECT MAX(id) FROM poems") ?? 0
        guard maxID > 0 else { return nil }
        let pick = Int64.random(in: 1...maxID)
        if let kind {
            return poems("SELECT \(Self.columns) FROM poems WHERE id >= ? AND kind = ? ORDER BY id LIMIT 1",
                         [.int(pick), .text(kind.rawValue)]).first
                ?? poems("SELECT \(Self.columns) FROM poems WHERE kind = ? ORDER BY id LIMIT 1", [.text(kind.rawValue)]).first
        }
        return poems("SELECT \(Self.columns) FROM poems WHERE id >= ? ORDER BY id LIMIT 1", [.int(pick)]).first
    }

    func search(_ keyword: String, limit: Int = 100) -> [Poem] {
        let k = keyword.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !k.isEmpty else { return [] }
        let like = "%\(k)%"
        // 先匹配题目和作者，再全文匹配名句
        var results = poems("""
            SELECT \(Self.columns) FROM poems
            WHERE title LIKE ? OR author = ?
            ORDER BY (daily_rank IS NULL), daily_rank, id LIMIT ?
            """, [.text(like), .text(k), .int(Int64(limit))])
        if results.count < limit {
            let seen = Set(results.map(\.id))
            let more = poems("""
                SELECT \(Self.columns) FROM poems WHERE content LIKE ?
                ORDER BY (daily_rank IS NULL), daily_rank, id LIMIT ?
                """, [.text(like), .int(Int64(limit - results.count))])
            results += more.filter { !seen.contains($0.id) }
        }
        return results
    }

    func poems(byAuthor author: String, limit: Int = 500) -> [Poem] {
        poems("SELECT \(Self.columns) FROM poems WHERE author = ? ORDER BY (daily_rank IS NULL), daily_rank, id LIMIT ?",
              [.text(author), .int(Int64(limit))])
    }

    func poems(byRhythmic rhythmic: String, limit: Int = 500) -> [Poem] {
        poems("SELECT \(Self.columns) FROM poems WHERE rhythmic = ? ORDER BY (daily_rank IS NULL), daily_rank, id LIMIT ?",
              [.text(rhythmic), .int(Int64(limit))])
    }

    func poems(inCollection collection: String, tag: String? = nil, offset: Int = 0, limit: Int = 60) -> [Poem] {
        if let tag {
            return poems("""
                SELECT \(Self.columns) FROM poems WHERE collection = ? AND ('|' || tags || '|') LIKE ?
                ORDER BY id LIMIT ? OFFSET ?
                """, [.text(collection), .text("%|\(tag)|%"), .int(Int64(limit)), .int(Int64(offset))])
        }
        return poems("SELECT \(Self.columns) FROM poems WHERE collection = ? ORDER BY id LIMIT ? OFFSET ?",
                     [.text(collection), .int(Int64(limit)), .int(Int64(offset))])
    }

    func poems(tagged tag: String, limit: Int = 400) -> [Poem] {
        poems("SELECT \(Self.columns) FROM poems WHERE ('|' || tags || '|') LIKE ? ORDER BY id LIMIT ?",
              [.text("%|\(tag)|%"), .int(Int64(limit))])
    }

    /// 最常见的词牌及其作品数
    func topRhythmics(limit: Int = 120) -> [(name: String, count: Int)] {
        rows("""
            SELECT rhythmic, COUNT(*) c FROM poems WHERE kind = 'ci' AND rhythmic IS NOT NULL
            GROUP BY rhythmic ORDER BY c DESC LIMIT ?
            """, [.int(Int64(limit))]) { stmt in
            (Self.text(stmt, 0) ?? "", Int(sqlite3_column_int64(stmt, 1)))
        }
    }

    /// 作品最多的词人
    func topCiAuthors(limit: Int = 80) -> [(name: String, count: Int)] {
        rows("""
            SELECT author, COUNT(*) c FROM poems WHERE kind = 'ci' AND author != '佚名' AND author != '无名氏'
            GROUP BY author ORDER BY c DESC LIMIT ?
            """, [.int(Int64(limit))]) { stmt in
            (Self.text(stmt, 0) ?? "", Int(sqlite3_column_int64(stmt, 1)))
        }
    }

    func author(named name: String, dynasty: String) -> Author? {
        let found = rows("""
            SELECT name, dynasty, description FROM authors WHERE name = ?
            ORDER BY (dynasty = ?) DESC LIMIT 1
            """, [.text(name), .text(dynasty)]) { stmt in
            Author(name: Self.text(stmt, 0) ?? "", dynasty: Self.text(stmt, 1) ?? "",
                   description: Self.text(stmt, 2) ?? "")
        }
        return found.first
    }

    // MARK: - SQLite 封装

    enum Arg { case int(Int64), text(String) }

    private static let columns =
        "id, title, author, dynasty, collection, kind, rhythmic, content, notes, prologue, tags, daily_rank"

    private func poems(_ sql: String, _ args: [Arg]) -> [Poem] {
        rows(sql, args) { stmt in
            Poem(
                id: sqlite3_column_int64(stmt, 0),
                title: Self.text(stmt, 1) ?? "",
                author: Self.text(stmt, 2) ?? "",
                dynasty: Self.text(stmt, 3) ?? "",
                collection: Self.text(stmt, 4) ?? "",
                kind: Poem.Kind(rawValue: Self.text(stmt, 5) ?? "") ?? .shi,
                rhythmic: Self.text(stmt, 6),
                lines: (Self.text(stmt, 7) ?? "").components(separatedBy: "\n"),
                notes: (Self.text(stmt, 8) ?? "").components(separatedBy: "\n").filter { !$0.isEmpty },
                prologue: Self.text(stmt, 9),
                tags: (Self.text(stmt, 10) ?? "").components(separatedBy: "|").filter { !$0.isEmpty },
                dailyRank: sqlite3_column_type(stmt, 11) == SQLITE_NULL ? nil : Int(sqlite3_column_int64(stmt, 11))
            )
        }
    }

    private func scalar(_ sql: String, _ args: [Arg] = []) -> Int64? {
        rows(sql, args) { sqlite3_column_int64($0, 0) }.first
    }

    private func rows<T>(_ sql: String, _ args: [Arg], map: (OpaquePointer) -> T) -> [T] {
        lock.lock()
        defer { lock.unlock() }
        guard let db else { return [] }
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK, let stmt else {
            print("SQL 错误: \(String(cString: sqlite3_errmsg(db)))")
            return []
        }
        defer { sqlite3_finalize(stmt) }
        let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        for (i, arg) in args.enumerated() {
            let idx = Int32(i + 1)
            switch arg {
            case .int(let v): sqlite3_bind_int64(stmt, idx, v)
            case .text(let v): sqlite3_bind_text(stmt, idx, v, -1, transient)
            }
        }
        var out: [T] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            out.append(map(stmt))
        }
        return out
    }

    private static func text(_ stmt: OpaquePointer, _ col: Int32) -> String? {
        guard let c = sqlite3_column_text(stmt, col) else { return nil }
        return String(cString: c)
    }
}
