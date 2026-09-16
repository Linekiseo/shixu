import AppKit
import SwiftUI

struct TypeSpecificInsightPanel: View {
    @ObservedObject var store: CaptureStore
    let item: CaptureItem

    @ViewBuilder
    var body: some View {
        switch item.kind {
        case .text:
            TextRecordInsight(item: item)
        case .image:
            ImageRecordInsight(item: item, imageURL: store.attachmentURL(for: item))
        case .web:
            WebRecordInsight(item: item)
        case .credential:
            CredentialRecordInsight(item: item)
        case .file:
            FileRecordInsight(item: item, isAvailable: store.attachmentURL(for: item) != nil)
        }
    }
}

private struct TextRecordInsight: View {
    let item: CaptureItem

    private var points: [String] { CaptureInsightService.keyPoints(for: item) }
    private var content: String { item.body.isEmpty ? item.title : item.body }

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(spacing: 5) {
                Image(systemName: item.textFormat?.systemImage ?? "text.quote")
                    .font(.title2)
                Text("\(content.count)")
                    .font(.headline.monospacedDigit())
                Text("字")
                    .font(.caption2)
            }
            .foregroundStyle(.indigo)
            .frame(width: 54)

            Rectangle()
                .fill(Color.indigo.opacity(0.24))
                .frame(width: 2)

            VStack(alignment: .leading, spacing: 12) {
                Text(item.textFormat.map { "\($0.title) 文档" } ?? "文字脉络")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.indigo)
                ForEach(Array(points.prefix(3).enumerated()), id: \.offset) { index, point in
                    HStack(alignment: .firstTextBaseline, spacing: 9) {
                        Text(String(format: "%02d", index + 1))
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(.indigo.opacity(0.7))
                        Text(point)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
        .padding(15)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            LinearGradient(colors: [.indigo.opacity(0.07), .clear], startPoint: .leading, endPoint: .trailing),
            in: RoundedRectangle(cornerRadius: 12)
        )
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.indigo.opacity(0.16)))
    }
}

private struct ImageRecordInsight: View {
    let item: CaptureItem
    let imageURL: URL?

    private var dimensions: String {
        guard let imageURL, let image = NSImage(contentsOf: imageURL) else { return "尺寸待读取" }
        return "\(Int(image.size.width)) × \(Int(image.size.height))"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("画面说明")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.orange)
                    Text(item.summary.isEmpty ? "这张画面尚未添加说明。" : item.summary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 12)
                Image(systemName: "camera.metering.multispot")
                    .font(.title2)
                    .foregroundStyle(.orange)
            }

            Divider().overlay(Color.orange.opacity(0.2))

            HStack(spacing: 0) {
                imageFact("画布", value: dimensions, icon: "aspectratio")
                Divider().frame(height: 34).padding(.horizontal, 12)
                imageFact("存储", value: item.originalLocation == nil ? "\(AppBrand.displayName)资料区" : "引用原图", icon: item.originalLocation == nil ? "internaldrive" : "link")
                Divider().frame(height: 34).padding(.horizontal, 12)
                imageFact("大小", value: CaptureInsightService.byteCount(item.fileSize), icon: "externaldrive")
            }
        }
        .padding(15)
        .background(Color.orange.opacity(0.055), in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.orange.opacity(0.18)))
    }

    private func imageFact(_ label: String, value: String, icon: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(label, systemImage: icon)
                .font(.caption2)
                .foregroundStyle(.tertiary)
            Text(value)
                .font(.caption.weight(.medium))
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct WebRecordInsight: View {
    let item: CaptureItem

    private var domain: String {
        (item.domain ?? URL(string: item.body)?.host(percentEncoded: false) ?? "未知站点")
            .replacingOccurrences(of: "www.", with: "")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Text(String(domain.prefix(1)).uppercased())
                    .font(.headline.bold())
                    .foregroundStyle(.white)
                    .frame(width: 36, height: 36)
                    .background(Color.blue.gradient, in: RoundedRectangle(cornerRadius: 9))
                VStack(alignment: .leading, spacing: 2) {
                    Text(domain)
                        .font(.caption.weight(.semibold))
                    Text("已进入「\(item.collection ?? "阅读")」")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                WebArchiveStatusBadge(item: item)
            }

            Text(item.summary.isEmpty ? "保存了网页地址，可在上方直接查看站点预览。" : item.summary)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineSpacing(3)

            HStack(spacing: 6) {
                Image(systemName: "link")
                Text(item.body)
                    .lineLimit(1)
                Spacer()
                Text(item.createdAt.suijiDayLabel)
            }
            .font(.caption2.monospaced())
            .foregroundStyle(.blue.opacity(0.8))

            Divider().overlay(Color.blue.opacity(0.16))
            HStack(spacing: 8) {
                Image(systemName: archiveStatusIcon)
                    .foregroundStyle((item.webArchiveState ?? .queued).tint)
                VStack(alignment: .leading, spacing: 2) {
                    Text(archiveStatusMessage)
                        .font(.caption2.weight(.medium))
                    if let root = item.webRootDomain {
                        Text("站点会话：\(root) · 同一根网站只需登录一次")
                            .font(.system(size: 9))
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                if let original = item.webArchiveOriginalSize,
                   let compressed = item.webArchiveCompressedSize,
                   original > 0 {
                    Text("压缩 \(Int((1 - Double(compressed) / Double(original)) * 100))%")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.green)
                }
            }
        }
        .padding(15)
        .background(
            LinearGradient(colors: [.blue.opacity(0.075), .cyan.opacity(0.025)], startPoint: .topLeading, endPoint: .bottomTrailing),
            in: RoundedRectangle(cornerRadius: 12)
        )
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.blue.opacity(0.18)))
    }

    private var archiveStatusIcon: String {
        switch item.webArchiveState ?? .queued {
        case .archived: "externaldrive.fill.badge.checkmark"
        case .failed, .queued: "link.circle.fill"
        case .capturing: "arrow.triangle.2.circlepath"
        case .loginRequired: "person.badge.shield.checkmark"
        }
    }

    private var archiveStatusMessage: String {
        switch item.webArchiveState ?? .queued {
        case .failed:
            "网页地址已保存，可随时打开；本机存档可以稍后再创建"
        case .queued:
            "网页地址已保存，正在等待创建本机存档"
        case .capturing:
            "正在创建本机网页存档"
        case .archived:
            item.webArchiveMessage ?? "已保留可离线查看的完整网页存档"
        case .loginRequired:
            item.webArchiveMessage ?? "网页地址已保存，登录站点后可以创建本机存档"
        }
    }
}

private struct CredentialRecordInsight: View {
    let item: CaptureItem

    private var isAPIKey: Bool { item.credentialType == .apiKey }

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(spacing: 7) {
                Image(systemName: "lock.shield.fill")
                    .font(.system(size: 26))
                    .foregroundStyle(SuijiTheme.accent)
                Text(isAPIKey ? "API 保险箱" : "本机保险箱")
                    .font(.system(size: 9, weight: .bold, design: .rounded))
                    .foregroundStyle(.secondary)
            }
            .frame(width: 74)

            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Label(
                        isAPIKey ? LLMProviderCatalog.displayName(for: item) : CredentialPlatformCatalog.displayName(for: item),
                        systemImage: isAPIKey ? LLMProviderCatalog.systemImage(for: item.platform) : CredentialPlatformCatalog.systemImage(for: item.platform)
                    )
                        .font(.caption.weight(.semibold))
                    Spacer()
                    Text(item.domain ?? (isAPIKey ? "Base URL 待配置" : "未绑定网页"))
                        .font(.caption2)
                        .foregroundStyle(item.domain == nil ? Color.orange : (isAPIKey ? Color.indigo : Color.blue))
                }
                Divider()
                safetyLine(isAPIKey ? "API Key 未写入记录与搜索" : "密码未写入记录正文", ok: true)
                safetyLine(isAPIKey ? "API Key 由 macOS 钥匙串保护" : "密码由 macOS 钥匙串保护", ok: item.secretKey != nil)
                safetyLine(
                    isAPIKey ? (item.apiBaseURL == nil ? "尚未配置 Base URL" : "已配置 API Base URL") : (item.loginURL == nil ? "尚未设置登录地址" : "已关联登录地址"),
                    ok: isAPIKey ? item.apiBaseURL != nil : item.loginURL != nil
                )
                Divider()
                HStack {
                    Text("敏感级别")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("受保护")
                        .foregroundStyle(SuijiTheme.accent)
                }
                .font(.caption2.weight(.medium))
            }
        }
        .padding(15)
        .background(SuijiTheme.accent.opacity(0.05), in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(SuijiTheme.accent.opacity(0.2)))
    }

    private func safetyLine(_ title: String, ok: Bool) -> some View {
        HStack(spacing: 9) {
            Image(systemName: ok ? "checkmark.circle.fill" : "circle.dashed")
                .foregroundStyle(ok ? Color.green : Color.orange)
            Text(title)
                .font(.caption)
            Spacer()
        }
    }
}

private struct FileRecordInsight: View {
    let item: CaptureItem
    let isAvailable: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack(spacing: 12) {
                Image(systemName: isAvailable ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                    .font(.title2)
                    .foregroundStyle(isAvailable ? Color.green : Color.orange)
                VStack(alignment: .leading, spacing: 2) {
                    Text(isAvailable ? "本地引用正常" : "原文件暂时失联")
                        .font(.caption.weight(.semibold))
                    Text(item.backupPath == nil ? "\(AppBrand.displayName)保存索引，不复制原文件" : "保留原文件引用，并有 LZFSE 无损备份")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text(item.fileExtension?.uppercased() ?? "FILE")
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .tracking(1.2)
                    .foregroundStyle(.teal)
            }

            if let path = item.originalLocation {
                VStack(alignment: .leading, spacing: 4) {
                    Text("原文件位置")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                    Text(path)
                        .font(.caption2.monospaced())
                        .lineLimit(2)
                        .textSelection(.enabled)
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.background.opacity(0.45), in: RoundedRectangle(cornerRadius: 8))
            }

            HStack {
                Label(CaptureInsightService.byteCount(item.fileSize ?? item.backupOriginalSize), systemImage: "externaldrive")
                Spacer()
                if let original = item.backupOriginalSize, let compressed = item.backupCompressedSize, original > 0 {
                    Label("备份节省 \(Int((1 - Double(compressed) / Double(original)) * 100))%", systemImage: "archivebox")
                } else {
                    Label("未创建备份", systemImage: "link")
                }
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
        .padding(15)
        .background(Color.teal.opacity(0.05), in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.teal.opacity(0.19)))
    }
}
