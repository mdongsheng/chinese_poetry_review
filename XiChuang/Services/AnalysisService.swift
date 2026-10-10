import Foundation

/// 调用 Claude Messages API 为一首作品生成「导读 / 译文 / 注释 / 赏析 / 背景 / 体裁」，并缓存到本地。
actor AnalysisService {
    static let shared = AnalysisService()

    enum Failure: LocalizedError {
        case noAPIKey
        case http(Int, String)
        case refusal
        case truncated
        case badResponse

        var errorDescription: String? {
            switch self {
            case .noAPIKey: "尚未设置 Claude API Key，请在「设置」中填写。"
            case .http(401, _): "API Key 无效，请在「设置」中检查。"
            case .http(429, _): "请求太频繁，请稍后再试。"
            case .http(let code, let msg): "解析服务暂时不可用（\(code)）：\(msg)"
            case .refusal: "这首作品暂时无法生成解析。"
            case .truncated: "解析内容过长被截断，请重试。"
            case .badResponse: "解析结果无法识别，请重试。"
            }
        }
    }

    private let endpoint = URL(string: "https://api.anthropic.com/v1/messages")!
    private let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 240
        config.timeoutIntervalForResource = 300
        return URLSession(configuration: config)
    }()
    private var inFlight: [Int64: Task<Analysis, Error>] = [:]

    // MARK: - 缓存

    private static let cacheDir: URL = {
        let dir = URL.applicationSupportDirectory.appending(path: "Analyses", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    private static func cacheURL(_ id: Int64) -> URL {
        cacheDir.appending(path: "\(id).json")
    }

    /// 同步读缓存，供通知排程等非异步场景使用
    static func cached(_ id: Int64) -> Analysis? {
        guard let data = try? Data(contentsOf: cacheURL(id)) else { return nil }
        return try? JSONDecoder().decode(Analysis.self, from: data)
    }

    // MARK: - 生成

    /// 有缓存直接返回；同一首作品的并发请求只发一次。
    func analysis(for poem: Poem, forceRefresh: Bool = false) async throws -> Analysis {
        if !forceRefresh, let cached = Self.cached(poem.id) { return cached }
        if let task = inFlight[poem.id] { return try await task.value }
        let task = Task { try await self.generate(poem) }
        inFlight[poem.id] = task
        defer { inFlight[poem.id] = nil }
        let result = try await task.value
        if let data = try? JSONEncoder().encode(result) {
            try? data.write(to: Self.cacheURL(poem.id), options: .atomic)
        }
        return result
    }

    private static let systemPrompt = """
    你是一位精通中国古典诗词的学者，为一款诗词 App 撰写每日推送的作品解析，读者是喜爱诗词的普通读者。
    要求：
    - 使用简体中文，文字典雅而平易，避免空泛套话。
    - 译文忠实原文，按原文句序分段。
    - 注释挑选读者可能不懂的字词、典故、地名、官职，每条简洁。
    - 赏析从意象、结构、手法、情感几个方面展开，可引用名家评语，但不要编造出处。
    - 创作背景只写有依据的内容；作者或写作年代存疑时如实说明，不要杜撰。
    - formIntro 介绍词牌（或曲牌、诗体）的来历与格律特点。
    """

    private func generate(_ poem: Poem) async throws -> Analysis {
        guard let apiKey = KeychainHelper.apiKey, !apiKey.isEmpty else { throw Failure.noAPIKey }
        let model = AppSettings.model

        var userText = """
        请解析这首\(poem.kind.label)：

        《\(poem.title)》 \(poem.byline)
        \(poem.fullText)
        """
        if !poem.notes.isEmpty {
            userText += "\n\n可参考的已有注释：\n" + poem.notes.joined(separator: "\n")
        }

        var body: [String: Any] = [
            "model": model.rawValue,
            "max_tokens": 16000,
            "thinking": ["type": "adaptive"],
            "output_config": [
                "effort": "medium",
                "format": ["type": "json_schema", "schema": Analysis.jsonSchema],
            ],
            "system": Self.systemPrompt,
            "messages": [["role": "user", "content": userText]],
        ]
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        if model.supportsServerFallback {
            // 安全分类器误拒时，由服务端自动换用推荐的回退模型重试
            body["fallbacks"] = "default"
            request.setValue("server-side-fallback-2026-07-01", forHTTPHeaderField: "anthropic-beta")
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await session.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else {
            throw Failure.http(status, Self.errorMessage(data))
        }

        let message = try JSONDecoder().decode(MessageResponse.self, from: data)
        switch message.stop_reason {
        case "refusal": throw Failure.refusal
        case "max_tokens": throw Failure.truncated
        default: break
        }
        guard let text = message.content.first(where: { $0.type == "text" })?.text,
              var analysis = try? JSONDecoder().decode(Analysis.self, from: Data(text.utf8)) else {
            throw Failure.badResponse
        }
        analysis.generatedAt = .now
        analysis.model = message.model ?? model.rawValue
        return analysis
    }

    private static func errorMessage(_ data: Data) -> String {
        struct Envelope: Decodable { struct E: Decodable { let message: String }; let error: E }
        return (try? JSONDecoder().decode(Envelope.self, from: data))?.error.message
            ?? String(data: data, encoding: .utf8) ?? ""
    }

    /// Messages API 响应里我们用到的部分
    private struct MessageResponse: Decodable {
        struct Block: Decodable {
            let type: String
            let text: String?
        }
        let model: String?
        let content: [Block]
        let stop_reason: String?
    }

    // MARK: - 预取

    /// 提前为接下来几天的推送生成解析，这样推送通知里就能带上导读。
    func prefetchUpcoming(days: Int = 3) async {
        guard KeychainHelper.hasAPIKey else { return }
        for item in DailyPoemProvider.upcoming(days: days) where Self.cached(item.poem.id) == nil {
            if Task.isCancelled { return }
            _ = try? await analysis(for: item.poem)
        }
    }
}
