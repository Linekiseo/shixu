import Foundation

struct AISearchPlan: Codable, Equatable, Sendable {
    var keywords: [String]
    var kind: String?
    var dateScope: String?
    var startDate: String?
    var endDate: String?
    var collection: String?
    var explanation: String

    var kindScope: SearchKindScope {
        SearchKindScope(rawValue: kind ?? "") ?? .all
    }

    var fallbackDateScope: SearchDateScope {
        SearchDateScope(rawValue: dateScope ?? "") ?? .all
    }

    func boundaryDate(_ value: String?, endOfDay: Bool) -> Date? {
        guard let value else { return nil }
        let components = value.split(separator: "-").compactMap { Int($0) }
        guard components.count == 3 else { return nil }
        var dateComponents = DateComponents()
        dateComponents.calendar = .current
        dateComponents.timeZone = .current
        dateComponents.year = components[0]
        dateComponents.month = components[1]
        dateComponents.day = components[2]
        guard let start = Calendar.current.date(from: dateComponents) else { return nil }
        if endOfDay {
            return Calendar.current.date(byAdding: .day, value: 1, to: start)
        }
        return start
    }
}

enum DeepSeekAISearchError: LocalizedError {
    case notConfigured
    case invalidEndpoint
    case service(String)
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .notConfigured: "AI 搜索尚未配置 API Key"
        case .invalidEndpoint: "DeepSeek API 地址无效"
        case .service(let message): message
        case .invalidResponse: "DeepSeek 没有返回可用的搜索条件"
        }
    }
}

enum DeepSeekAISearchService {
    static let keychainAccount = "ai-search.deepseek.api-key"
    static let defaultBaseURL = "https://api.deepseek.com"
    static let defaultModel = "deepseek-v4-flash"

    static var isConfigured: Bool {
        !(KeychainService.load(key: keychainAccount) ?? "").isEmpty
    }

    static func configurationStatus() async -> Bool {
        await Task.detached(priority: .utility) { isConfigured }.value
    }

    static func saveAPIKey(_ value: String) -> Bool {
        let clean = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return false }
        return KeychainService.save(secret: clean, key: keychainAccount)
    }

    static func saveAPIKeyAsync(_ value: String) async -> Bool {
        await Task.detached(priority: .userInitiated) { saveAPIKey(value) }.value
    }

    static func removeAPIKey() {
        KeychainService.delete(key: keychainAccount)
    }

    static func interpret(_ query: String) async throws -> AISearchPlan {
        let apiKey = await Task.detached(priority: .userInitiated) {
            KeychainService.load(key: keychainAccount)
        }.value
        guard let apiKey, !apiKey.isEmpty else {
            throw DeepSeekAISearchError.notConfigured
        }
        let baseURL = UserDefaults.standard.string(forKey: "deepSeekAISearchBaseURL") ?? defaultBaseURL
        guard let endpoint = endpointURL(from: baseURL) else {
            throw DeepSeekAISearchError.invalidEndpoint
        }

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 24
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONEncoder().encode(
            ChatRequest(
                model: defaultModel,
                messages: [
                    Message(role: "system", content: systemPrompt),
                    Message(role: "user", content: "今天是 \(Date.now.formatted(.iso8601.year().month().day()))。请把下面的查询转换为 json 搜索计划：\n\(query)")
                ],
                responseFormat: ResponseFormat(type: "json_object"),
                thinking: Thinking(type: "disabled"),
                maxTokens: 500,
                stream: false
            )
        )

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw DeepSeekAISearchError.invalidResponse }
        guard 200..<300 ~= http.statusCode else {
            let apiMessage = (try? JSONDecoder().decode(APIErrorEnvelope.self, from: data).error.message)
            throw DeepSeekAISearchError.service(apiMessage ?? "DeepSeek 请求失败（\(http.statusCode)）")
        }
        let envelope = try JSONDecoder().decode(ChatResponse.self, from: data)
        guard let content = envelope.choices.first?.message.content else {
            throw DeepSeekAISearchError.invalidResponse
        }
        return try decodePlan(from: content)
    }

    static func decodePlan(from content: String) throws -> AISearchPlan {
        let clean = content
            .replacingOccurrences(of: "```json", with: "")
            .replacingOccurrences(of: "```", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let data = clean.data(using: .utf8),
              var plan = try? JSONDecoder().decode(AISearchPlan.self, from: data) else {
            throw DeepSeekAISearchError.invalidResponse
        }
        plan.keywords = Array(Set(plan.keywords
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }))
            .prefix(12)
            .map { $0 }
        plan.explanation = plan.explanation.trimmingCharacters(in: .whitespacesAndNewlines)
        return plan
    }

    private static func endpointURL(from value: String) -> URL? {
        guard var components = URLComponents(string: value.trimmingCharacters(in: .whitespacesAndNewlines)),
              components.scheme == "https", components.host != nil else { return nil }
        let cleanPath = components.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        components.path = cleanPath.hasSuffix("chat/completions")
            ? "/\(cleanPath)"
            : "/\(cleanPath.isEmpty ? "" : cleanPath + "/")chat/completions"
        return components.url
    }

    private static let systemPrompt = """
    你是本机资料库的查询解析器。你看不到用户资料，只负责把自然语言查询转换为 JSON 搜索计划。
    只输出 JSON 对象，格式：
    {"keywords":["关键词或同义词"],"kind":"all|text|image|web|credential|file","dateScope":"all|today|week|month","startDate":"YYYY-MM-DD 或 null","endDate":"YYYY-MM-DD 或 null","collection":"集合名或 null","explanation":"一句简短中文说明"}
    关键词用于本机匹配，请保留专有名词并补充少量常见同义词。任意日期范围优先使用 startDate/endDate；无法判断时使用 dateScope。不得索要或虚构资料内容。
    """

    private struct Message: Encodable { let role: String; let content: String }
    private struct ResponseFormat: Encodable { let type: String }
    private struct Thinking: Encodable { let type: String }
    private struct ChatRequest: Encodable {
        let model: String
        let messages: [Message]
        let responseFormat: ResponseFormat
        let thinking: Thinking
        let maxTokens: Int
        let stream: Bool

        enum CodingKeys: String, CodingKey {
            case model, messages, thinking, stream
            case responseFormat = "response_format"
            case maxTokens = "max_tokens"
        }
    }
    private struct ChatResponse: Decodable {
        struct Choice: Decodable {
            struct ResponseMessage: Decodable { let content: String? }
            let message: ResponseMessage
        }
        let choices: [Choice]
    }
    private struct APIErrorEnvelope: Decodable {
        struct APIError: Decodable { let message: String }
        let error: APIError
    }
}
