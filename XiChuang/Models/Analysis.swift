import Foundation

/// 由 Claude 生成的一首作品的解析，按 JSON 缓存在本地。
struct Analysis: Codable, Hashable, Sendable {
    struct Annotation: Codable, Hashable, Sendable {
        let term: String
        let explanation: String
    }

    /// 一句话导读，用于推送通知正文
    let summary: String
    /// 白话译文
    let translation: String
    /// 字词注释
    let annotations: [Annotation]
    /// 赏析
    let appreciation: String
    /// 创作背景
    let background: String
    /// 词牌 / 体裁简介
    let formIntro: String

    var generatedAt: Date?
    var model: String?

    /// 传给 Claude 结构化输出的 JSON Schema，字段与上面一一对应
    static let jsonSchema: [String: Any] = [
        "type": "object",
        "properties": [
            "summary": ["type": "string", "description": "二十字以内的一句话导读，点出意境或情感"],
            "translation": ["type": "string", "description": "逐句的白话译文，按原文分段"],
            "annotations": [
                "type": "array",
                "items": [
                    "type": "object",
                    "properties": [
                        "term": ["type": "string"],
                        "explanation": ["type": "string"],
                    ],
                    "required": ["term", "explanation"],
                    "additionalProperties": false,
                ],
            ],
            "appreciation": ["type": "string", "description": "三到五段赏析"],
            "background": ["type": "string", "description": "创作背景，不确定时说明存疑"],
            "formIntro": ["type": "string", "description": "词牌、曲牌或诗体的简介"],
        ],
        "required": ["summary", "translation", "annotations", "appreciation", "background", "formIntro"],
        "additionalProperties": false,
    ]
}
