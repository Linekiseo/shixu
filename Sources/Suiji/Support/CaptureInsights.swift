import Foundation

struct CaptureInsight: Identifiable, Hashable {
    let id = UUID()
    var icon: String
    var label: String
    var value: String
}

enum CaptureInsightService {
    static func summaryTitle(for item: CaptureItem) -> String {
        switch item.kind {
        case .text: item.textFormat.map { "\($0.title) 文档" } ?? "这段内容在说什么"
        case .image: "画面重点"
        case .web: "为什么值得留下"
        case .credential: item.credentialType == .apiKey ? "API 密钥配置" : "登录信息概览"
        case .file: "文件状态"
        }
    }

    static func keyPoints(for item: CaptureItem) -> [String] {
        var points: [String] = []
        let summarySentences = sentences(in: item.summary)
        points.append(contentsOf: summarySentences.prefix(2))

        switch item.kind {
        case .text:
            if points.isEmpty { points.append(contentsOf: sentences(in: item.body).prefix(2)) }
            if let format = item.textFormat { points.append("已保存为 \(item.fileName ?? ".\(format.fileExtension) 文件")") }
            if !item.tags.isEmpty { points.append("主题：\(item.tags.prefix(3).joined(separator: "、"))") }
        case .image:
            points.append(item.originalLocation == nil ? "图片保存在\(AppBrand.displayName)本机资料区" : "保持对本地原图的引用")
        case .web:
            if let domain = item.domain { points.append("来自 \(domain)") }
            points.append("网页只保存索引与预览，不复制整页内容")
        case .credential:
            if item.credentialType == .apiKey {
                points.append("服务商：\(LLMProviderCatalog.displayName(for: item))")
                points.append("密钥名称：\(item.username ?? "默认密钥")")
                points.append(item.apiBaseURL.map { "Base URL：\($0)" } ?? "Base URL 待配置")
                points.append("API Key 不进入正文与搜索，仅由 macOS 钥匙串保存")
            } else {
                points.append("平台：\(CredentialPlatformCatalog.displayName(for: item))")
                points.append("账号：\(item.username ?? "待补充")")
                points.append("密码正文不落盘，仅由 macOS 钥匙串保存")
            }
        case .file:
            points.append(item.backupPath == nil ? "只引用原文件，没有额外副本" : "保留原文件引用和无损压缩备份")
            if let location = item.originalLocation {
                points.append("位置：\(URL(fileURLWithPath: location).deletingLastPathComponent().lastPathComponent)")
            }
        }

        var seen = Set<String>()
        return points
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && seen.insert($0).inserted }
            .prefix(4)
            .map { $0 }
    }

    static func facts(for item: CaptureItem) -> [CaptureInsight] {
        var facts = [
            CaptureInsight(icon: "arrow.down.to.line", label: "来源", value: item.source),
            CaptureInsight(icon: "clock", label: "记录于", value: item.createdAt.formatted(date: .abbreviated, time: .shortened))
        ]

        if let collection = item.collection {
            facts.append(CaptureInsight(icon: "square.stack.3d.up", label: "集合", value: collection))
        }

        switch item.kind {
        case .text:
            facts.append(CaptureInsight(icon: "character.cursor.ibeam", label: "长度", value: "\(item.body.count) 字"))
            if let format = item.textFormat {
                facts.append(CaptureInsight(icon: format.systemImage, label: "格式", value: "\(format.title) · .\(format.fileExtension)"))
                facts.append(CaptureInsight(icon: "externaldrive", label: "文件大小", value: byteCount(item.fileSize)))
            }
        case .image:
            facts.append(CaptureInsight(icon: "photo", label: "格式", value: item.fileExtension ?? "图片"))
            if let size = item.fileSize { facts.append(CaptureInsight(icon: "externaldrive", label: "大小", value: byteCount(size))) }
        case .web:
            if let domain = item.domain { facts.append(CaptureInsight(icon: "network", label: "站点", value: domain)) }
        case .credential:
            if item.credentialType == .apiKey {
                facts.append(CaptureInsight(icon: LLMProviderCatalog.systemImage(for: item.platform), label: "服务商", value: LLMProviderCatalog.displayName(for: item)))
                if let domain = item.domain { facts.append(CaptureInsight(icon: "network", label: "API 主机", value: domain)) }
            } else {
                facts.append(CaptureInsight(icon: CredentialPlatformCatalog.systemImage(for: item.platform), label: "平台", value: CredentialPlatformCatalog.displayName(for: item)))
            }
            facts.append(CaptureInsight(icon: "checkmark.shield", label: "保护", value: "macOS 钥匙串"))
        case .file:
            facts.append(CaptureInsight(icon: "doc", label: "格式", value: item.fileExtension?.isEmpty == false ? item.fileExtension! : "文件"))
            if let size = item.fileSize ?? item.backupOriginalSize {
                facts.append(CaptureInsight(icon: "externaldrive", label: "大小", value: byteCount(size)))
            }
        }
        return facts
    }

    static func byteCount(_ value: Int64?) -> String {
        guard let value else { return "未知" }
        return ByteCountFormatter.string(fromByteCount: value, countStyle: .file)
    }

    private static func sentences(in text: String) -> [String] {
        text
            .components(separatedBy: CharacterSet(charactersIn: "。！？!?\n"))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .map { $0.count > 72 ? String($0.prefix(72)) + "…" : $0 }
    }
}
