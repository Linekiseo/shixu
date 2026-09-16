import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// 收件箱专用的横向处理卡。它与“全部记录”的竖版瀑布流完全分离，
/// 优先给原始画面足够空间，同时把整理动作集中在稳定的信息栏里。
struct InboxRecordCard: View {
    @ObservedObject var store: CaptureStore
    let item: CaptureItem
    let selected: Bool
    @State private var isDropTarget = false
    @State private var isShowingOfflineArchive = false

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 0) {
                artwork
                    .frame(minWidth: 280, maxWidth: .infinity)
                    .frame(height: 204)
                    .clipped()

                Rectangle()
                    .fill(item.kind.tint.opacity(0.16))
                    .frame(width: 1)
                    .padding(.vertical, 14)

                informationArea
                    .frame(width: 328, height: 204, alignment: .topLeading)
            }
            .frame(minWidth: 640)

            VStack(spacing: 0) {
                artwork.frame(height: 210).clipped()
                informationArea
            }
        }
        .background(
            LinearGradient(
                colors: [Color(nsColor: .controlBackgroundColor).opacity(0.9), item.kind.tint.opacity(0.035)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 16)
        )
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay {
            RoundedRectangle(cornerRadius: 16)
                .stroke(isDropTarget ? Color.green : (selected ? item.kind.tint : item.kind.tint.opacity(0.18)), lineWidth: isDropTarget ? 3 : (selected ? 2 : 1))
        }
        .contentShape(RoundedRectangle(cornerRadius: 16))
        .onTapGesture { store.selectedItemID = item.id }
        .onTapGesture(count: 2) { CapturePrimaryAction.perform(store: store, item: item) }
        .onDrag { CaptureDragProvider.make(store: store, item: item) }
        .onDrop(of: [.shixuCaptureRecord, .utf8PlainText, .url], isTargeted: $isDropTarget, perform: receiveDrop)
        .contextMenu { managementMenu }
        .sheet(isPresented: $isShowingOfflineArchive) {
            if let archiveURL = store.webArchiveURL(for: item), let liveURL = URL(string: item.body) {
                OfflineWebArchiveSheet(archiveURL: archiveURL, liveURL: liveURL, item: item)
            }
        }
        .help("单击查看详情 · 双击打开 · 拖到另一条记录上组合")
    }

    @ViewBuilder
    private var artwork: some View {
        switch item.kind {
        case .image:
            if let url = store.attachmentURL(for: item), let image = NSImage(contentsOf: url) {
                Color.clear.overlay { Image(nsImage: image).resizable().scaledToFill() }.clipped()
                    .overlay(alignment: .topLeading) { artworkBadge("画面", icon: "camera.viewfinder") }
            } else {
                placeholder(icon: "photo", title: "图片等待连接")
            }
        case .web:
            if let url = URL(string: item.body) {
                WebArtworkPreview(url: url, localArchive: item.webArchivePreviewSource)
                    .allowsHitTesting(false)
            } else {
                placeholder(icon: "globe", title: "网页地址不可用")
            }
        case .file:
            if let url = store.attachmentURL(for: item) {
                FileThumbnailPreview(url: url, fallbackExtension: item.fileExtension)
                    .allowsHitTesting(false)
                    .overlay(alignment: .topLeading) { artworkBadge("文件预览", icon: "doc.text.image") }
            } else {
                placeholder(icon: "doc.badge.ellipsis", title: "文件等待重新连接")
            }
        case .credential:
            ZStack {
                LinearGradient(colors: [item.kind.tint.opacity(0.2), .purple.opacity(0.045)], startPoint: .topLeading, endPoint: .bottomTrailing)
                VStack(spacing: 11) {
                    CredentialPlatformMark(platform: item.platform, credentialType: item.credentialType ?? .account, size: 64)
                    Text(item.platform ?? (item.credentialType == .apiKey ? "LLM API" : "安全账号"))
                        .font(.headline)
                    Label("由 macOS 钥匙串保护", systemImage: "checkmark.shield.fill")
                        .font(.caption2)
                        .foregroundStyle(.green)
                }
            }
        case .text:
            ZStack(alignment: .topLeading) {
                LinearGradient(colors: [.indigo.opacity(0.14), Color(nsColor: .textBackgroundColor).opacity(0.82)], startPoint: .topLeading, endPoint: .bottomTrailing)
                VStack(alignment: .leading, spacing: 8) {
                    artworkBadge(item.textFormat?.title ?? "随手文字", icon: item.textFormat?.systemImage ?? "text.quote")
                    Text(item.body.isEmpty ? item.title : item.body)
                        .font(item.textFormat == nil ? .custom("Songti SC", size: 14) : .system(size: 10, design: .monospaced))
                        .lineSpacing(4)
                        .lineLimit(7)
                }
                .padding(13)
            }
        }
    }

    private var informationArea: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 7) {
                Label(typeLabel, systemImage: item.kind.systemImage)
                    .font(.system(size: 9, weight: .bold, design: .rounded))
                    .tracking(0.8)
                    .foregroundStyle(item.kind.tint)
                Spacer()
                Button { store.toggleFavorite(item.id) } label: {
                    Image(systemName: item.isFavorite ? "star.fill" : "star")
                }
                .buttonStyle(.plain)
                .foregroundStyle(item.isFavorite ? Color.yellow : Color.secondary)
            }

            Text(item.title)
                .font(.custom("Songti SC", size: 18).weight(.semibold))
                .lineLimit(2)

            Text(detailLine)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineSpacing(3)
                .lineLimit(3)

            Spacer(minLength: 0)

            HStack(spacing: 7) {
                Label(item.sourceApplication ?? item.source, systemImage: item.sourceApplication == nil ? "tray" : "app.badge")
                    .lineLimit(1)
                Text("·")
                Text(item.createdAt.suijiTime).monospacedDigit()
                Spacer(minLength: 4)
                quickAction
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
        .padding(15)
    }

    private var typeLabel: String {
        switch item.kind {
        case .web: item.domain ?? "网页"
        case .file: [item.fileExtension?.uppercased(), "本地文件"].compactMap { $0 }.joined(separator: " · ")
        case .credential: item.credentialType == .apiKey ? "LLM API" : "账号"
        case .text: item.textFormat?.title ?? "文字"
        case .image: item.fileExtension?.uppercased() ?? "图片"
        }
    }

    private var detailLine: String {
        switch item.kind {
        case .web:
            return item.summary.isEmpty ? item.body : item.summary
        case .file:
            let status = store.attachmentURL(for: item) == nil ? "原文件失联" : "原文件可访问"
            return "\(CaptureInsightService.byteCount(item.fileSize ?? item.backupOriginalSize)) · \(status)\(item.backupPath == nil ? " · 链接原文件" : " · 含压缩备份")"
        case .credential:
            if item.credentialType == .apiKey {
                return item.apiBaseURL.map { "Base URL · \($0)" } ?? "密钥已安全保存，Base URL 待配置"
            }
            return item.loginURL.map { "已绑定登录网页 · \($0)" } ?? "账号凭据仅保存在本机钥匙串"
        case .text:
            return item.summary.isEmpty ? String(item.body.prefix(180)) : item.summary
        case .image:
            if let url = store.attachmentURL(for: item), let image = NSImage(contentsOf: url) {
                return "\(Int(image.size.width)) × \(Int(image.size.height)) · \(CaptureInsightService.byteCount(item.fileSize))"
            }
            return CaptureInsightService.byteCount(item.fileSize)
        }
    }

    @ViewBuilder
    private var quickAction: some View {
        switch item.kind {
        case .image, .file, .text:
            if store.attachmentURL(for: item) != nil {
                Button("预览", systemImage: "eye") { CapturePrimaryAction.preview(store: store, item: item) }
                    .buttonStyle(.borderless)
                    .foregroundStyle(item.kind.tint)
            }
        case .web:
            if item.webArchiveState == .archived, store.webArchiveURL(for: item) != nil {
                Button("本机画面", systemImage: "archivebox.fill") { isShowingOfflineArchive = true }
                    .buttonStyle(.borderless)
                    .foregroundStyle(.green)
            } else if let url = URL(string: item.body) {
                Button("打开", systemImage: "arrow.up.right") { NSWorkspace.shared.open(url) }
                    .buttonStyle(.borderless)
                    .foregroundStyle(.blue)
            }
        case .credential:
            if let address = item.apiBaseURL ?? item.loginURL, let url = URL(string: address) {
                Button("打开", systemImage: "arrow.up.right") { NSWorkspace.shared.open(url) }
                    .buttonStyle(.borderless)
                    .foregroundStyle(item.kind.tint)
            }
        }
    }

    private func artworkBadge(_ title: String, icon: String) -> some View {
        Label(title, systemImage: icon)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(.black.opacity(0.5), in: Capsule())
            .padding(10)
    }

    private func placeholder(icon: String, title: String) -> some View {
        ZStack {
            item.kind.tint.opacity(0.08)
            VStack(spacing: 9) {
                Image(systemName: icon).font(.system(size: 38, weight: .light))
                Text(title).font(.caption)
            }
            .foregroundStyle(item.kind.tint)
        }
    }

    @ViewBuilder
    private var managementMenu: some View {
        Button("打开", systemImage: "arrow.up.forward.app") { CapturePrimaryAction.perform(store: store, item: item) }
        Button("预览", systemImage: "eye") { CapturePrimaryAction.preview(store: store, item: item) }
            .disabled(item.kind == .web ? store.webArchiveURL(for: item) == nil : store.attachmentURL(for: item) == nil)
        Divider()
        Button(item.isFavorite ? "取消收藏" : "收藏") { store.toggleFavorite(item.id) }
        if item.compositionID != nil {
            Button("移出组合", systemImage: "rectangle.portrait.and.arrow.right") { store.removeFromComposition(item.id) }
        }
        Button("移到回收站", role: .destructive) { store.moveToTrash(item.id) }
    }

    private func receiveDrop(_ providers: [NSItemProvider]) -> Bool {
        let targetID = item.id
        if let provider = providers.first(where: { $0.hasItemConformingToTypeIdentifier(UTType.shixuCaptureRecord.identifier) }) {
            CaptureDragProvider.loadRecordID(from: provider) { sourceID in
                guard let sourceID else { return }
                _ = store.combine(sourceID, onto: targetID)
            }
            return true
        }
        for provider in providers {
            if provider.canLoadObject(ofClass: NSURL.self) {
                provider.loadObject(ofClass: NSURL.self) { object, _ in
                    guard let url = object as? URL else { return }
                    Task { @MainActor in _ = store.handleDroppedURL(url, onto: targetID) }
                }
                return true
            }
            if provider.canLoadObject(ofClass: NSString.self) {
                provider.loadObject(ofClass: NSString.self) { object, _ in
                    guard let value = object as? String else { return }
                    Task { @MainActor in _ = store.handleDroppedText(value, onto: targetID) }
                }
                return true
            }
        }
        return false
    }
}
