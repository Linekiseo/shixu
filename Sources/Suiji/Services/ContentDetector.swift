import Foundation
import UniformTypeIdentifiers

struct DetectedContent: Sendable {
    var kind: CaptureKind
    var title: String
    var body: String
    var summary: String
    var tags: [String]
    var username: String?
    var password: String?
    var credentialType: CredentialRecordType? = nil
    var platform: String? = nil
    var apiBaseURL: String? = nil
    var textFormat: TextContentFormat? = nil
}

enum ContentDetector {
    static func detect(text rawText: String, forcedKind: CaptureKind? = nil) -> DetectedContent {
        let text = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        let kind = forcedKind ?? inferredKind(for: text)

        switch kind {
        case .web:
            let normalized = normalizedURLString(text)
            let host = URL(string: normalized)?.host(percentEncoded: false) ?? shortTitle(text)
            return DetectedContent(
                kind: .web,
                title: host.replacingOccurrences(of: "www.", with: ""),
                body: normalized,
                summary: "已保存网页地址，之后可通过域名、标签或记忆中的片段找到它。",
                tags: ["网页", "待读"],
                username: nil,
                password: nil
            )

        case .credential:
            if let apiKey = LLMAPIKeyDetector.detect(in: text) {
                let platform = apiKey.provider ?? "OpenAI 兼容 / 待确认"
                return DetectedContent(
                    kind: .credential,
                    title: "\(platform) · API 密钥",
                    body: "API 密钥已安全保存",
                    summary: apiKey.baseURL == nil
                        ? "密钥仅存入 macOS 钥匙串；服务商或 Base URL 仍待确认。"
                        : "密钥仅存入 macOS 钥匙串，并已配置对应的 API Base URL。",
                    tags: ["API密钥", "受保护", platform],
                    username: apiKey.keyLabel,
                    password: apiKey.key,
                    credentialType: .apiKey,
                    platform: platform,
                    apiBaseURL: apiKey.baseURL
                )
            }
            let username = firstMatch(in: text, patterns: [
                #"(?:账号|用户名|邮箱|user(?:name)?|email)\s*[：:]\s*([^\s，,]+)"#,
                #"(?:账号|用户名|邮箱|user(?:name)?|email)\s+([^\s，,]+)"#
            ]) ?? "待补充"
            let password = firstMatch(in: text, patterns: [
                #"(?:密码|口令|password|pass)\s*[：:]\s*([^\s，,]+)"#,
                #"(?:密码|口令|password|pass)\s+([^\s，,]+)"#
            ])
            let serviceName = text.components(separatedBy: .newlines).first?
                .replacingOccurrences(of: #"(?:账号|用户名|邮箱|密码|口令|username|password).*$"#, with: "", options: [.regularExpression, .caseInsensitive])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return DetectedContent(
                kind: .credential,
                title: serviceName?.isEmpty == false ? serviceName! : "新登录信息",
                body: "账号：\(username)",
                summary: "敏感字段已单独存入 macOS 钥匙串；记录正文不会保存明文密码。",
                tags: ["账号", "受保护"],
                username: username,
                password: password,
                credentialType: .account
            )

        case .text:
            let format = TextFormatDetector.detect(text)
            let title = format.flatMap { TextFormatDetector.suggestedTitle(for: text, format: $0) } ?? shortTitle(text)
            var tags = inferredTextTags(text)
            if let format, !tags.contains(format.title) { tags.append(format.title) }
            return DetectedContent(
                kind: .text,
                title: title,
                body: text,
                summary: format.map { "已识别为\($0.title)并保存为 .\($0.fileExtension) 文件。" }
                    ?? (text.count > 80 ? String(text.prefix(76)) + "…" : text),
                tags: Array(tags.prefix(4)),
                username: nil,
                password: nil,
                textFormat: format
            )

        case .image:
            return DetectedContent(kind: .image, title: text.isEmpty ? "新截图" : shortTitle(text), body: text, summary: "一张保存到\(AppBrand.displayName)的图片或截图。", tags: ["图片", "未整理"], username: nil, password: nil)

        case .file:
            return DetectedContent(kind: .file, title: text.isEmpty ? "新文件" : shortTitle(text), body: text, summary: "一个保存到\(AppBrand.displayName)的文件。", tags: ["文件", "未整理"], username: nil, password: nil)
        }
    }

    static func kind(for fileURL: URL) -> CaptureKind {
        guard let type = UTType(filenameExtension: fileURL.pathExtension) else { return .file }
        return type.conforms(to: .image) ? .image : .file
    }

    static func inferredKind(for text: String) -> CaptureKind {
        if LLMAPIKeyDetector.detect(in: text) != nil { return .credential }
        if looksLikeCredential(text) { return .credential }
        if URL(string: normalizedURLString(text))?.scheme?.hasPrefix("http") == true,
           !text.contains("\n"), text.contains(".") { return .web }
        return .text
    }

    private static func looksLikeCredential(_ text: String) -> Bool {
        let lower = text.lowercased()
        let hasAccount = ["账号", "用户名", "邮箱", "username", "email"].contains { lower.contains($0) }
        let hasPassword = ["密码", "口令", "password", "pass:"].contains { lower.contains($0) }
        let hasOTPLabel = ["验证码", "动态码", "一次性密码", "otp", "verification code"].contains { lower.contains($0) }
        let rawOTP = lower.range(of: #"^\d{4,8}$"#, options: .regularExpression) != nil
        return (hasAccount && hasPassword) || hasOTPLabel || rawOTP
    }

    private static func normalizedURLString(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.lowercased().hasPrefix("http://") || trimmed.lowercased().hasPrefix("https://") { return trimmed }
        return "https://" + trimmed
    }

    private static func shortTitle(_ text: String) -> String {
        let singleLine = text.replacingOccurrences(of: "\n", with: " ").trimmingCharacters(in: .whitespaces)
        if singleLine.isEmpty { return "未命名记录" }
        return singleLine.count > 38 ? String(singleLine.prefix(38)) + "…" : singleLine
    }

    private static func inferredTextTags(_ text: String) -> [String] {
        var tags = ["文字"]
        if text.contains("想") || text.contains("灵感") { tags.append("灵感") }
        if text.contains("下一步") || text.contains("待办") { tags.append("行动") }
        if text.contains("书") || text.contains("阅读") { tags.append("阅读") }
        return Array(tags.prefix(3))
    }

    private static func firstMatch(in text: String, patterns: [String]) -> String? {
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { continue }
            let range = NSRange(text.startIndex..., in: text)
            guard let match = regex.firstMatch(in: text, range: range), match.numberOfRanges > 1,
                  let captureRange = Range(match.range(at: 1), in: text) else { continue }
            return String(text[captureRange])
        }
        return nil
    }
}
