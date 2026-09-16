import Foundation

struct CredentialPlatformPreset: Identifiable, Hashable, Sendable {
    let name: String
    let domains: [String]
    let loginURL: String
    let systemImage: String

    var id: String { name }
}

enum CredentialPlatformCatalog {
    static let customSelection = "__custom_platform__"

    static let presets: [CredentialPlatformPreset] = [
        .init(name: "Apple", domains: ["apple.com", "icloud.com"], loginURL: "https://account.apple.com", systemImage: "apple.logo"),
        .init(name: "Google", domains: ["google.com", "gmail.com"], loginURL: "https://accounts.google.com", systemImage: "g.circle.fill"),
        .init(name: "Microsoft", domains: ["microsoft.com", "live.com", "outlook.com"], loginURL: "https://account.microsoft.com", systemImage: "square.grid.2x2.fill"),
        .init(name: "GitHub", domains: ["github.com"], loginURL: "https://github.com/login", systemImage: "chevron.left.forwardslash.chevron.right"),
        .init(name: "OpenAI", domains: ["openai.com", "chatgpt.com"], loginURL: "https://auth.openai.com", systemImage: "sparkles"),
        .init(name: "微信", domains: ["weixin.qq.com", "wechat.com"], loginURL: "https://weixin.qq.com", systemImage: "message.fill"),
        .init(name: "QQ", domains: ["qq.com"], loginURL: "https://qzone.qq.com", systemImage: "bubble.left.and.bubble.right.fill"),
        .init(name: "淘宝", domains: ["taobao.com", "tmall.com"], loginURL: "https://login.taobao.com", systemImage: "bag.fill"),
        .init(name: "支付宝", domains: ["alipay.com"], loginURL: "https://auth.alipay.com", systemImage: "creditcard.fill"),
        .init(name: "微博", domains: ["weibo.com"], loginURL: "https://weibo.com/login.php", systemImage: "dot.radiowaves.left.and.right"),
        .init(name: "知乎", domains: ["zhihu.com"], loginURL: "https://www.zhihu.com/signin", systemImage: "questionmark.circle.fill"),
        .init(name: "小红书", domains: ["xiaohongshu.com"], loginURL: "https://www.xiaohongshu.com", systemImage: "book.closed.fill"),
        .init(name: "抖音", domains: ["douyin.com"], loginURL: "https://www.douyin.com", systemImage: "music.note"),
        .init(name: "Notion", domains: ["notion.so"], loginURL: "https://www.notion.so/login", systemImage: "square.text.square.fill"),
        .init(name: "Figma", domains: ["figma.com"], loginURL: "https://www.figma.com/login", systemImage: "paintbrush.pointed.fill"),
        .init(name: "Slack", domains: ["slack.com"], loginURL: "https://slack.com/signin", systemImage: "number"),
        .init(name: "Discord", domains: ["discord.com"], loginURL: "https://discord.com/login", systemImage: "gamecontroller.fill")
    ]

    static func preset(named name: String?) -> CredentialPlatformPreset? {
        guard let name else { return nil }
        return presets.first { $0.name.caseInsensitiveCompare(name) == .orderedSame }
    }

    static func infer(title: String, domain: String?, loginURL: String?) -> String? {
        let normalizedDomain = (domain ?? URL(string: loginURL ?? "")?.host(percentEncoded: false) ?? "")
            .lowercased()
            .replacingOccurrences(of: "www.", with: "")
        let lowerTitle = title.lowercased()

        if let matched = presets.first(where: { preset in
            lowerTitle.contains(preset.name.lowercased()) || preset.domains.contains { knownDomain in
                normalizedDomain == knownDomain || normalizedDomain.hasSuffix("." + knownDomain)
            }
        }) {
            return matched.name
        }

        let cleaned = title
            .replacingOccurrences(of: "账号", with: "")
            .replacingOccurrences(of: "登录信息", with: "")
            .replacingOccurrences(of: "新登录信息", with: "")
            .trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: "·-—")))
        if !cleaned.isEmpty { return cleaned }
        if !normalizedDomain.isEmpty { return normalizedDomain }
        return nil
    }

    static func displayName(for item: CaptureItem) -> String {
        item.platform
            ?? infer(title: item.title, domain: item.domain, loginURL: item.loginURL)
            ?? "未指定平台"
    }

    static func systemImage(for platform: String?) -> String {
        preset(named: platform)?.systemImage ?? "person.crop.square.filled.and.at.rectangle"
    }
}
