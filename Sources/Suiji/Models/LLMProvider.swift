import Foundation

struct LLMProviderPreset: Identifiable, Hashable, Sendable {
    let name: String
    let baseURL: String
    let consoleURL: String
    let systemImage: String
    let keyPrefixes: [String]
    let environmentLabels: [String]

    var id: String { name }
}

enum LLMProviderCatalog {
    static let customSelection = "__custom_llm_provider__"

    static let presets: [LLMProviderPreset] = [
        .init(
            name: "OpenAI",
            baseURL: "https://api.openai.com/v1",
            consoleURL: "https://platform.openai.com/api-keys",
            systemImage: "sparkles",
            keyPrefixes: ["sk-proj-", "sk-svcacct-"],
            environmentLabels: ["OPENAI_API_KEY"]
        ),
        .init(
            name: "Anthropic Claude",
            baseURL: "https://api.anthropic.com/v1",
            consoleURL: "https://console.anthropic.com/settings/keys",
            systemImage: "a.circle.fill",
            keyPrefixes: ["sk-ant-"],
            environmentLabels: ["ANTHROPIC_API_KEY", "CLAUDE_API_KEY"]
        ),
        .init(
            name: "Google Gemini",
            baseURL: "https://generativelanguage.googleapis.com/v1beta",
            consoleURL: "https://aistudio.google.com/app/apikey",
            systemImage: "diamond.fill",
            keyPrefixes: ["AIza"],
            environmentLabels: ["GEMINI_API_KEY", "GOOGLE_API_KEY"]
        ),
        .init(
            name: "OpenRouter",
            baseURL: "https://openrouter.ai/api/v1",
            consoleURL: "https://openrouter.ai/settings/keys",
            systemImage: "arrow.triangle.branch",
            keyPrefixes: ["sk-or-v1-"],
            environmentLabels: ["OPENROUTER_API_KEY"]
        ),
        .init(
            name: "DeepSeek",
            baseURL: "https://api.deepseek.com",
            consoleURL: "https://platform.deepseek.com/api_keys",
            systemImage: "brain.head.profile",
            keyPrefixes: [],
            environmentLabels: ["DEEPSEEK_API_KEY"]
        ),
        .init(
            name: "Groq",
            baseURL: "https://api.groq.com/openai/v1",
            consoleURL: "https://console.groq.com/keys",
            systemImage: "bolt.fill",
            keyPrefixes: ["gsk_"],
            environmentLabels: ["GROQ_API_KEY"]
        ),
        .init(
            name: "xAI",
            baseURL: "https://api.x.ai/v1",
            consoleURL: "https://console.x.ai",
            systemImage: "xmark.circle.fill",
            keyPrefixes: ["xai-"],
            environmentLabels: ["XAI_API_KEY"]
        ),
        .init(
            name: "Mistral AI",
            baseURL: "https://api.mistral.ai/v1",
            consoleURL: "https://console.mistral.ai/api-keys",
            systemImage: "wind",
            keyPrefixes: [],
            environmentLabels: ["MISTRAL_API_KEY"]
        )
    ]

    static func preset(named name: String?) -> LLMProviderPreset? {
        guard let name else { return nil }
        return presets.first { $0.name.caseInsensitiveCompare(name) == .orderedSame }
    }

    static func preset(forEnvironmentLabel label: String) -> LLMProviderPreset? {
        let upper = label.uppercased()
        return presets.first { $0.environmentLabels.contains(upper) }
    }

    static func preset(forKey key: String) -> LLMProviderPreset? {
        presets.first { preset in preset.keyPrefixes.contains { key.hasPrefix($0) } }
    }

    static func preset(forBaseURL value: String) -> LLMProviderPreset? {
        guard let host = URL(string: value)?.host(percentEncoded: false)?.lowercased() else { return nil }
        return presets.first { preset in
            guard let knownHost = URL(string: preset.baseURL)?.host(percentEncoded: false)?.lowercased() else { return false }
            return host == knownHost || host.hasSuffix("." + knownHost)
        }
    }

    static func displayName(for item: CaptureItem) -> String {
        item.platform?.isEmpty == false ? item.platform! : "OpenAI 兼容 / 待确认"
    }

    static func systemImage(for platform: String?) -> String {
        preset(named: platform)?.systemImage ?? "key.horizontal.fill"
    }
}

struct DetectedLLMAPIKey: Sendable, Equatable {
    let key: String
    let provider: String?
    let keyLabel: String
    let baseURL: String?
}

enum LLMAPIKeyDetector {
    static func detect(in text: String) -> DetectedLLMAPIKey? {
        if let labeled = labeledKey(in: text) {
            let provider = LLMProviderCatalog.preset(forEnvironmentLabel: labeled.label)
                ?? LLMProviderCatalog.preset(forKey: labeled.value)
            return DetectedLLMAPIKey(
                key: labeled.value,
                provider: provider?.name,
                keyLabel: labeled.label,
                baseURL: labeledBaseURL(in: text) ?? provider?.baseURL
            )
        }

        if let value = firstMatch(
            in: text,
            pattern: #"(?<![A-Za-z0-9_-])((?:sk-ant-|sk-or-v1-|sk-proj-|sk-svcacct-|gsk_|xai-|AIza)[A-Za-z0-9._-]{12,})(?![A-Za-z0-9_-])"#
        ) {
            let provider = LLMProviderCatalog.preset(forKey: value)
            return DetectedLLMAPIKey(
                key: value,
                provider: provider?.name,
                keyLabel: "默认密钥",
                baseURL: labeledBaseURL(in: text) ?? provider?.baseURL
            )
        }

        if let value = firstMatch(
            in: text,
            pattern: #"(?<![A-Za-z0-9_-])(sk-[A-Za-z0-9._-]{20,})(?![A-Za-z0-9_-])"#
        ) {
            return DetectedLLMAPIKey(
                key: value,
                provider: nil,
                keyLabel: "默认密钥",
                baseURL: labeledBaseURL(in: text)
            )
        }
        return nil
    }

    private static func labeledKey(in text: String) -> (label: String, value: String)? {
        let knownLabels = LLMProviderCatalog.presets
            .flatMap(\.environmentLabels)
            .joined(separator: "|")
        let pattern = #"(?im)\b("# + knownLabels + #"|[A-Z][A-Z0-9_]*(?:API_KEY|ACCESS_TOKEN))\b\s*[:=]\s*[\"']?([A-Za-z0-9._-]{16,})[\"']?"#
        guard let match = matches(in: text, pattern: pattern, captureCount: 2) else { return nil }
        return (match[0].uppercased(), match[1])
    }

    private static func labeledBaseURL(in text: String) -> String? {
        guard let value = firstMatch(
            in: text,
            pattern: #"(?im)\b(?:[A-Z0-9_]*BASE_URL|ENDPOINT|API_URL)\b\s*[:=]\s*[\"']?(https?://[^\s\"']+)"#
        ) else { return nil }
        return value.trimmingCharacters(in: CharacterSet(charactersIn: ",;"))
    }

    private static func firstMatch(in text: String, pattern: String) -> String? {
        matches(in: text, pattern: pattern, captureCount: 1)?.first
    }

    private static func matches(in text: String, pattern: String, captureCount: Int) -> [String]? {
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let result = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              result.numberOfRanges > captureCount else { return nil }
        return (1...captureCount).compactMap { index in
            guard let range = Range(result.range(at: index), in: text) else { return nil }
            return String(text[range])
        }
    }
}
