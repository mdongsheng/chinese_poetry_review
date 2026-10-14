import Foundation

/// 调用 Claude 或 DeepSeek，为一首作品生成「导读 / 译文 / 注释 / 赏析 / 背景 / 体裁」，并缓存到本地。
/// 缓存与服务无关：换了服务，已生成的解析照常显示。
actor AnalysisService {
    static let shared = AnalysisService()

    enum Failure: LocalizedError {
        case noAPIKey(AnalysisProvider)
        case http(Int, String)
        case refusal
        case truncated
        case badResponse
        case badBaseURL(AnalysisProvider)

        var errorDescription: String? {
            switch self {
            case .noAPIKey(let p): "尚未设置 \(p.displayName) 的 API Key，请在「设置」中填写。"
            case .http(401, _): "API Key 无效，请在「设置」中检查。"
            case .http(402, _): "账户余额不足，请充值后再试。"
            case .http(429, _): "请求太频繁，请稍后再试。"
            case .http(let code, let msg): "解析服务暂时不可用（\(code)）：\(msg)"
            case .refusal: "这首作品暂时无法生成解析。"
            case .truncated: "解析内容过长被截断，请重试。"
            case .badResponse: "解析结果无法识别，请重试。"
            case .badBaseURL(let p): "\(p.displayName) 的接口地址格式不对，请在「设置」中检查。"
            }
        }
    }

    /// 接口地址：设置里填了就用自定义的，否则用官方地址
    private static func baseURL(_ provider: AnalysisProvider) throws -> URL {
        guard let url = AppSettings.baseURL(for: provider) else { throw Failure.badBaseURL(provider) }
        return url
    }

    /// Anthropic Messages 接口。地址已经以 /v1 结尾（不少代理这样写）时不再重复加
    private static func claudeEndpoint() throws -> URL {
        let base = try baseURL(.claude)
        return base.path().hasSuffix("/v1") ? base.appending(path: "messages") : base.appending(path: "v1/messages")
    }
    private static let session: URLSession = {
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

    /// 当前选中的服务是否已填写 API Key
    static var isConfigured: Bool { KeychainHelper.hasAPIKey(for: AppSettings.provider) }

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

    /// DeepSeek 的 JSON 模式只保证输出合法 JSON，字段要在提示里写清楚
    private static let deepSeekFormat = """
    只输出一个 JSON 对象，不要输出其它文字。字段如下：
    {
      "summary": "二十字以内的一句话导读",
      "translation": "白话译文，按原文分段，段间用换行",
      "annotations": [{"term": "字词", "explanation": "解释"}],
      "appreciation": "三到五段赏析，段间用换行",
      "background": "创作背景",
      "formIntro": "词牌、曲牌或诗体简介"
    }
    """

    private static func userPrompt(_ poem: Poem) -> String {
        var text = """
        请解析这首\(poem.kind.label)：

        《\(poem.title)》 \(poem.byline)
        \(poem.fullText)
        """
        if !poem.notes.isEmpty {
            text += "\n\n可参考的已有注释：\n" + poem.notes.joined(separator: "\n")
        }
        return text
    }

    private func generate(_ poem: Poem) async throws -> Analysis {
        let provider = AppSettings.provider
        guard let apiKey = KeychainHelper.apiKey(for: provider), !apiKey.isEmpty else {
            throw Failure.noAPIKey(provider)
        }
        let result: (analysis: Analysis, model: String)
        switch provider {
        case .claude: result = try await Self.generateWithClaude(poem, apiKey: apiKey)
        case .deepseek: result = try await Self.generateWithDeepSeek(poem, apiKey: apiKey)
        }
        var analysis = result.analysis
        analysis.generatedAt = .now
        analysis.model = result.model
        return analysis
    }

    // MARK: - Claude

    private static func generateWithClaude(_ poem: Poem, apiKey: String) async throws -> (Analysis, String) {
        let model = AppSettings.model
        var body: [String: Any] = [
            "model": model.rawValue,
            "max_tokens": 16000,
            "thinking": ["type": "adaptive"],
            "output_config": [
                "effort": "medium",
                "format": ["type": "json_schema", "schema": Analysis.jsonSchema],
            ],
            "system": systemPrompt,
            "messages": [["role": "user", "content": userPrompt(poem)]],
        ]
        var request = URLRequest(url: try claudeEndpoint())
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

        let data = try await send(request)
        let message = try JSONDecoder().decode(ClaudeResponse.self, from: data)
        switch message.stop_reason {
        case "refusal": throw Failure.refusal
        case "max_tokens": throw Failure.truncated
        default: break
        }
        guard let text = message.content.first(where: { $0.type == "text" })?.text else {
            throw Failure.badResponse
        }
        return (try decodeAnalysis(text), message.model ?? model.rawValue)
    }

    /// Messages API 响应里用到的部分
    private struct ClaudeResponse: Decodable {
        struct Block: Decodable {
            let type: String
            let text: String?
        }
        let model: String?
        let content: [Block]
        let stop_reason: String?
    }

    // MARK: - DeepSeek（OpenAI 兼容的 Chat Completions 接口）

    private static func generateWithDeepSeek(_ poem: Poem, apiKey: String) async throws -> (Analysis, String) {
        let model = AppSettings.deepSeekModel
        let body: [String: Any] = [
            "model": model,
            "max_tokens": 8192,
            "response_format": ["type": "json_object"],
            "messages": [
                ["role": "system", "content": systemPrompt + "\n" + deepSeekFormat],
                ["role": "user", "content": userPrompt(poem)],
            ],
        ]
        var request = URLRequest(url: try baseURL(.deepseek).appending(path: "chat/completions"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "authorization")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let data = try await send(request)
        let response = try JSONDecoder().decode(ChatResponse.self, from: data)
        guard let choice = response.choices.first else { throw Failure.badResponse }
        switch choice.finish_reason {
        case "length": throw Failure.truncated
        case "content_filter": throw Failure.refusal
        default: break
        }
        guard let text = choice.message.content, !text.isEmpty else { throw Failure.badResponse }
        return (try decodeAnalysis(text), response.model ?? model)
    }

    /// 设置页用：列出这个 Key 能用的 DeepSeek 模型
    static func deepSeekModels(apiKey: String) async throws -> [String] {
        var request = URLRequest(url: try baseURL(.deepseek).appending(path: "models"))
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "authorization")
        struct List: Decodable { struct Model: Decodable { let id: String }; let data: [Model] }
        return try JSONDecoder().decode(List.self, from: try await send(request)).data.map(\.id).sorted()
    }

    private struct ChatResponse: Decodable {
        struct Choice: Decodable {
            struct Message: Decodable { let content: String? }
            let message: Message
            let finish_reason: String?
        }
        let model: String?
        let choices: [Choice]
    }

    // MARK: - 共用

    private static func send(_ request: URLRequest) async throws -> Data {
        let (data, response) = try await session.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else { throw Failure.http(status, errorMessage(data)) }
        return data
    }

    private static func decodeAnalysis(_ text: String) throws -> Analysis {
        // 个别模型会把 JSON 包在 ```json 代码块里
        var json = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if let start = json.firstIndex(of: "{"), let end = json.lastIndex(of: "}"), start < end {
            json = String(json[start...end])
        }
        guard let analysis = try? JSONDecoder().decode(Analysis.self, from: Data(json.utf8)) else {
            throw Failure.badResponse
        }
        return analysis
    }

    /// Anthropic 与 DeepSeek 的错误体都是 {"error": {"message": …}}
    private static func errorMessage(_ data: Data) -> String {
        struct Envelope: Decodable { struct E: Decodable { let message: String }; let error: E }
        return (try? JSONDecoder().decode(Envelope.self, from: data))?.error.message
            ?? String(data: data, encoding: .utf8) ?? ""
    }

    // MARK: - 预取

    /// 提前为接下来几天的推送生成解析，这样推送通知里就能带上导读。
    func prefetchUpcoming(days: Int = 3) async {
        guard Self.isConfigured else { return }
        for item in DailyPoemProvider.upcoming(days: days) where Self.cached(item.poem.id) == nil {
            if Task.isCancelled { return }
            _ = try? await analysis(for: item.poem)
        }
    }
}
