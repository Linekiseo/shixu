import AppKit
import SwiftUI

struct InspectorView: View {
    @ObservedObject var store: CaptureStore

    var body: some View {
        Group {
            if let item = store.selectedItem {
                InspectorContent(store: store, item: item)
                    .id(item.id)
            }
        }
    }
}

private struct InspectorContent: View {
    @ObservedObject var store: CaptureStore
    let item: CaptureItem
    @State private var revealSecret = false
    @State private var copiedAction: String?
    @State private var isAddingTag = false
    @State private var newTag = ""
    @State private var isAddingCollection = false
    @State private var newCollection = ""
    @State private var isEditingNote = false
    @State private var noteDraft: String
    @State private var isShowingOfflineWebArchive = false
    @State private var isShowingWebsiteSession = false
    @State private var isEditingCredential = false

    init(store: CaptureStore, item: CaptureItem) {
        self.store = store
        self.item = item
        _noteDraft = State(initialValue: item.userNote ?? "")
    }

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 16) {
                titleBlock
                hero
                actionBar
                InspectorSourceContextCard(item: item)
                if item.compositionID != nil { InspectorCompositionEditor(store: store, item: item) }
                TypeSpecificInsightPanel(store: store, item: item)
                organizationCard
                originalContentCard
                relatedCard
            }
            .padding(18)
        }
        .background(VerticalScrollIndicatorSuppressor().frame(width: 0, height: 0))
        .background(.regularMaterial.opacity(0.32))
        .sheet(isPresented: $isEditingCredential) {
            CredentialCaptureSheet(store: store, item: item)
        }
        .sheet(isPresented: $isShowingOfflineWebArchive) {
            if let archiveURL = store.webArchiveURL(for: item), let liveURL = URL(string: item.body) {
                OfflineWebArchiveSheet(archiveURL: archiveURL, liveURL: liveURL, item: item)
            }
        }
        .sheet(isPresented: $isShowingWebsiteSession) {
            WebsiteSessionArchiveSheet(store: store, item: item)
        }
    }

    @ViewBuilder
    private var hero: some View {
        switch item.kind {
        case .image:
            imageHero
        case .web:
            webHero
        case .file:
            fileHero
        case .credential:
            credentialHero
        case .text:
            textHero
        }
    }

    private var imageHero: some View {
        Group {
            if let url = store.attachmentURL(for: item), let image = NSImage(contentsOf: url) {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity, maxHeight: 260)
                    .overlay(alignment: .bottomTrailing) {
                        Button("放大查看", systemImage: "arrow.up.left.and.arrow.down.right") {
                            CapturePrimaryAction.preview(store: store, item: item)
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                        .tint(.black.opacity(0.68))
                        .padding(10)
                    }
            } else {
                previewPlaceholder(icon: "photo", title: "图片暂时不可用")
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(SuijiTheme.divider))
    }

    @ViewBuilder
    private var webHero: some View {
        if let url = URL(string: item.body) {
            WebArtworkPreview(url: url, localArchive: item.webArchivePreviewSource)
                .frame(height: 190)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.blue.opacity(0.2)))
                .contentShape(Rectangle())
                .onTapGesture {
                    if item.webArchiveState == .archived, store.webArchiveURL(for: item) != nil {
                        isShowingOfflineWebArchive = true
                    }
                }
                .help(item.webArchiveState == .archived ? "打开保存在本机的网页快照" : "网页封面")
        } else {
            previewPlaceholder(icon: "globe", title: "网页地址不可用")
        }
    }

    @ViewBuilder
    private var fileHero: some View {
        if let url = store.attachmentURL(for: item) {
            FileThumbnailPreview(url: url, fallbackExtension: item.fileExtension)
                .frame(height: 220)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.teal.opacity(0.22)))
                .overlay(alignment: .bottomTrailing) {
                    Button("完整预览", systemImage: "eye.fill") { CapturePrimaryAction.preview(store: store, item: item) }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                        .tint(.teal)
                        .padding(10)
                }
        } else {
            VStack(spacing: 11) {
                FileTypeIcon(url: nil, fallbackExtension: item.fileExtension, size: 64)
                Text("原文件暂时失联")
                    .font(.headline)
                Text(item.backupPath == nil ? "重新添加原文件即可恢复预览" : "仍可从压缩备份恢复内容")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, minHeight: 190)
            .background(Color.teal.opacity(0.055), in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.teal.opacity(0.2)))
        }
    }

    private var credentialHero: some View {
        let isAPIKey = item.credentialType == .apiKey
        let platform = isAPIKey ? LLMProviderCatalog.displayName(for: item) : CredentialPlatformCatalog.displayName(for: item)
        return VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 13) {
                CredentialPlatformMark(platform: item.platform, credentialType: isAPIKey ? .apiKey : .account, size: 58)
                VStack(alignment: .leading, spacing: 4) {
                    Text(platform)
                        .font(.headline)
                    Label(
                        isAPIKey
                            ? (item.apiBaseURL == nil ? "API Base URL 待配置" : "已配置 \(item.domain ?? "API 调用地址")")
                            : (item.loginURL == nil ? "本机账号 · 钥匙串保护" : "已绑定 \(item.domain ?? "Web 登录页")"),
                        systemImage: isAPIKey ? "network" : (item.loginURL == nil ? "checkmark.shield" : "globe")
                    )
                        .font(.caption2)
                        .foregroundStyle(isAPIKey ? (item.apiBaseURL == nil ? Color.orange : Color.indigo) : (item.loginURL == nil ? Color.green : Color.blue))
                }
                Spacer()
                Button("编辑", systemImage: "slider.horizontal.3") { isEditingCredential = true }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }

            credentialField(label: isAPIKey ? "密钥名称" : "账号", value: item.username ?? "待补充", actionKey: "username")
            credentialField(label: isAPIKey ? "API Key" : "密码", value: revealSecret ? (store.secret(for: item) ?? "未保存") : "••••••••••••", actionKey: "password", canReveal: true)
            if isAPIKey {
                credentialField(label: "Base URL", value: item.apiBaseURL ?? "待配置", actionKey: "baseURL")
            }
        }
        .padding(15)
        .background((isAPIKey ? Color.indigo : SuijiTheme.accent).opacity(0.055), in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke((isAPIKey ? Color.indigo : SuijiTheme.accent).opacity(0.22)))
    }

    private var textHero: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: item.textFormat?.systemImage ?? "quote.opening")
                    .font(.title)
                    .foregroundStyle(Color.indigo.opacity(0.7))
                if let format = item.textFormat {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(format.title) 文档")
                            .font(.caption.weight(.semibold))
                        Text(item.fileName ?? ".\(format.fileExtension)")
                            .font(.caption2.monospaced())
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
            }
            Text(item.body.isEmpty ? item.title : item.body)
                .font(item.textFormat == nil ? .custom("Songti SC", size: 18) : .system(size: 13, design: .monospaced))
                .lineSpacing(7)
                .textSelection(.enabled)
                .lineLimit(10)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.indigo.opacity(0.055), in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.indigo.opacity(0.18)))
    }

    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .top) {
                Label(item.kind.cardLabel, systemImage: item.kind.systemImage)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(item.kind.tint)
                Spacer()
                Button { store.toggleFavorite(item.id) } label: {
                    Image(systemName: item.isFavorite ? "star.fill" : "star")
                }
                .buttonStyle(.plain)
                .foregroundStyle(item.isFavorite ? SuijiTheme.accent : .secondary)
            }
            Text(item.title)
                .font(.custom("Songti SC", size: 21).weight(.semibold))
                .textSelection(.enabled)
            if let reason = item.organizationReason {
                Label(reason, systemImage: "wand.and.stars")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var actionBar: some View {
        HStack(spacing: 8) {
            switch item.kind {
            case .text:
                actionButton("复制", icon: copiedAction == "text" ? "checkmark" : "doc.on.doc") {
                    copy(item.body.isEmpty ? item.title : item.body, key: "text")
                }
                if item.textFormat != nil {
                    actionButton("预览文件", icon: "eye") { CapturePrimaryAction.preview(store: store, item: item) }
                        .disabled(store.attachmentURL(for: item) == nil)
                    actionButton("打开文件", icon: "arrow.up.forward.app") { openAttachment() }
                        .disabled(store.attachmentURL(for: item) == nil)
                }
            case .image:
                actionButton("放大预览", icon: "magnifyingglass") { CapturePrimaryAction.preview(store: store, item: item) }
                actionButton("打开原图", icon: "arrow.up.forward.app") { openAttachment() }
            case .web:
                actionButton("打开网页", icon: "arrow.up.right") {
                    if let url = URL(string: item.body) { NSWorkspace.shared.open(url) }
                }
                actionButton("复制链接", icon: copiedAction == "url" ? "checkmark" : "link") { copy(item.body, key: "url") }
                if item.webArchiveState == .archived, store.webArchiveURL(for: item) != nil {
                    actionButton("查看离线快照", icon: "archivebox.fill") { isShowingOfflineWebArchive = true }
                    actionButton("登录后更新", icon: "person.badge.key.fill") { isShowingWebsiteSession = true }
                } else if item.webArchiveState == .loginRequired {
                    actionButton("登录并归档", icon: "person.badge.key.fill") { isShowingWebsiteSession = true }
                } else if item.webArchiveState != .capturing {
                    actionButton("备份网页", icon: "archivebox") { store.requestWebArchive(for: item.id) }
                }
            case .credential:
                actionButton(item.credentialType == .apiKey ? "编辑 API 配置" : "编辑平台", icon: "slider.horizontal.3") { isEditingCredential = true }
                if item.credentialType == .apiKey, let baseURL = item.apiBaseURL {
                    actionButton("复制 Base URL", icon: copiedAction == "baseURL" ? "checkmark" : "network") {
                        copy(baseURL, key: "baseURL")
                    }
                } else if let loginURL = item.loginURL {
                    actionButton("前往登录", icon: "arrow.up.right") {
                        if let url = URL(string: loginURL) { NSWorkspace.shared.open(url) }
                    }
                }
            case .file:
                actionButton("完整预览", icon: "eye") { CapturePrimaryAction.preview(store: store, item: item) }
                    .disabled(store.attachmentURL(for: item) == nil)
                actionButton("打开", icon: "arrow.up.forward.app") { openAttachment() }
                    .disabled(store.attachmentURL(for: item) == nil)
                actionButton("在访达显示", icon: "folder") { revealOriginal() }
                    .disabled(FileReferenceService.resolve(bookmark: item.fileBookmark, fallbackPath: item.originalLocation) == nil)
                if item.backupPath == nil {
                    actionButton("压缩备份", icon: "archivebox") { store.createCompressedBackup(for: item.id) }
                        .disabled(store.attachmentURL(for: item) == nil)
                }
            }
            Spacer(minLength: 0)
        }
    }

    private var organizationCard: some View {
        DetailCard(title: "整理方式", icon: "square.stack.3d.up") {
            VStack(alignment: .leading, spacing: 13) {
                HStack {
                    Text("集合").font(.caption2).foregroundStyle(.tertiary)
                    Spacer()
                    Menu {
                        Button("未归档") { store.assignCollection(nil, to: item.id) }
                        Divider()
                        ForEach(store.availableCollections, id: \.self) { collection in
                            Button {
                                store.assignCollection(collection, to: item.id)
                            } label: {
                                if item.collection == collection { Label(collection, systemImage: "checkmark") }
                                else { Text(collection) }
                            }
                        }
                    } label: {
                        Label(item.collection ?? "未归档", systemImage: "folder")
                    }
                    .menuStyle(.borderlessButton)
                    Button { isAddingCollection.toggle() } label: { Image(systemName: "plus") }
                        .buttonStyle(.borderless)
                        .help("新建集合")
                }

                if isAddingCollection {
                    HStack {
                        TextField("新集合名称", text: $newCollection)
                            .textFieldStyle(.roundedBorder)
                            .onSubmit(addCollection)
                        Button("归入", action: addCollection)
                            .buttonStyle(.borderedProminent)
                            .tint(item.kind.tint)
                    }
                }

                Divider()

                Text("标签").font(.caption2).foregroundStyle(.tertiary)
                FlowLayout(spacing: 6) {
                    ForEach(item.tags, id: \.self) { tag in
                        Button {
                            store.removeTag(tag, from: item.id)
                        } label: {
                            HStack(spacing: 4) {
                                Text(tag)
                                Image(systemName: "xmark")
                                    .font(.system(size: 7, weight: .bold))
                            }
                            .font(.caption2)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 5)
                            .background(.quaternary.opacity(0.55), in: Capsule())
                        }
                        .buttonStyle(.plain)
                        .help("移除标签 \(tag)")
                    }
                    Button { isAddingTag.toggle() } label: {
                        Label("标签", systemImage: "plus")
                            .font(.caption2)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 5)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }

                if isAddingTag {
                    HStack {
                        TextField("输入标签", text: $newTag)
                            .textFieldStyle(.roundedBorder)
                            .onSubmit(addTag)
                        Button("添加", action: addTag).buttonStyle(.bordered)
                    }
                }

                Divider()

                HStack {
                    Text("你的备注").font(.caption2).foregroundStyle(.tertiary)
                    Spacer()
                    if !isEditingNote {
                        Button(item.userNote == nil ? "添加备注" : "编辑") {
                            noteDraft = item.userNote ?? ""
                            isEditingNote = true
                        }
                        .buttonStyle(.borderless)
                        .controlSize(.small)
                    }
                }

                if isEditingNote {
                    TextEditor(text: $noteDraft)
                        .font(.caption)
                        .scrollContentBackground(.hidden)
                        .frame(minHeight: 54, maxHeight: 84)
                        .padding(7)
                        .background(.quaternary.opacity(0.18), in: RoundedRectangle(cornerRadius: 7))
                        .overlay(RoundedRectangle(cornerRadius: 7).stroke(SuijiTheme.divider))
                    HStack {
                        Spacer()
                        Button("取消") {
                            noteDraft = item.userNote ?? ""
                            isEditingNote = false
                        }
                        .buttonStyle(.borderless)
                        Button("保存") {
                            store.updateNote(noteDraft, for: item.id)
                            isEditingNote = false
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                } else if let note = item.userNote, !note.isEmpty {
                    Text(note)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineSpacing(3)
                        .textSelection(.enabled)
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(.quaternary.opacity(0.14), in: RoundedRectangle(cornerRadius: 8))
                }
            }
        }
    }

    @ViewBuilder
    private var originalContentCard: some View {
        if !item.body.isEmpty && item.kind == .web {
            DetailCard(title: "原始链接", icon: "link") {
                if let url = URL(string: item.body) {
                    Link(destination: url) {
                        HStack { Text(item.body).lineLimit(3); Spacer(); Image(systemName: "arrow.up.right") }
                    }.font(.caption.monospaced())
                }
            }
        } else if let format = item.textFormat {
            DetailCard(title: "生成的本机文件", icon: format.systemImage) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text(item.fileName ?? ".\(format.fileExtension) 文件")
                            .font(.caption.monospaced())
                            .textSelection(.enabled)
                        Spacer()
                        Text(CaptureInsightService.byteCount(item.fileSize))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    Text("文件由粘贴原文生成；记录正文继续用于全文搜索，文件内容与原文保持一致。")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Button("在访达显示", systemImage: "folder") {
                        if let url = store.attachmentURL(for: item) {
                            NSWorkspace.shared.activateFileViewerSelecting([url])
                        }
                    }
                    .buttonStyle(.borderless)
                    .disabled(store.attachmentURL(for: item) == nil)
                }
            }
        }
    }

    private var relatedCard: some View {
        DetailCard(title: "相关内容", icon: "point.3.connected.trianglepath.dotted") {
            let related = store.relatedMatches(to: item)
            if related.isEmpty {
                Text("暂未找到共享主题、标签、站点或明确组合关系的内容。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                VStack(spacing: 8) {
                    ForEach(related) { match in
                        Button {
                            store.revealInAll(match.item.id)
                        } label: {
                            HStack(alignment: .top, spacing: 10) {
                                Image(systemName: match.item.kind.systemImage)
                                    .foregroundStyle(match.item.kind.tint)
                                    .frame(width: 30, height: 30)
                                    .background(match.item.kind.tint.opacity(0.11), in: RoundedRectangle(cornerRadius: 8))
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(match.item.title)
                                        .font(.caption.weight(.semibold))
                                        .lineLimit(2)
                                    Text(match.reasons.joined(separator: " · "))
                                        .font(.system(size: 9))
                                        .foregroundStyle(.secondary)
                                        .lineLimit(2)
                                }
                                Spacer()
                                Text(match.item.createdAt.suijiDayLabel)
                                    .font(.system(size: 9).monospacedDigit())
                                    .foregroundStyle(.tertiary)
                            }
                            .padding(9)
                            .contentShape(RoundedRectangle(cornerRadius: 9))
                            .background(.quaternary.opacity(0.14), in: RoundedRectangle(cornerRadius: 9))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private func credentialField(label: String, value: String, actionKey: String, canReveal: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(label).font(.caption2).foregroundStyle(.tertiary)
            HStack {
                Text(value).font(.caption.monospaced()).textSelection(.enabled)
                Spacer()
                if canReveal {
                    Button { revealSecret.toggle() } label: { Image(systemName: revealSecret ? "eye.slash" : "eye") }
                        .buttonStyle(.plain)
                }
                Button {
                    let copyValue = actionKey == "password" ? (store.secret(for: item) ?? "") : value
                    copy(copyValue, key: actionKey)
                } label: {
                    Image(systemName: copiedAction == actionKey ? "checkmark" : "doc.on.doc")
                }
                .buttonStyle(.plain)
            }
        }
        .padding(10)
        .background(.background.opacity(0.38), in: RoundedRectangle(cornerRadius: 8))
    }

    private func actionButton(_ title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) { Label(title, systemImage: icon) }
            .buttonStyle(.bordered)
            .controlSize(.small)
    }

    private func previewPlaceholder(icon: String, title: String) -> some View {
        VStack(spacing: 9) {
            Image(systemName: icon).font(.largeTitle).foregroundStyle(.tertiary)
            Text(title).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 170)
        .background(.quaternary.opacity(0.16))
    }

    private func openAttachment() {
        if let url = store.attachmentURL(for: item) { NSWorkspace.shared.open(url) }
    }

    private func revealOriginal() {
        if let url = FileReferenceService.resolve(bookmark: item.fileBookmark, fallbackPath: item.originalLocation) {
            NSWorkspace.shared.activateFileViewerSelecting([url])
        }
    }

    private func copy(_ value: String, key: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(value, forType: .string)
        copiedAction = key
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.3))
            if copiedAction == key { copiedAction = nil }
        }
    }

    private func addTag() {
        let clean = newTag.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { isAddingTag = false; return }
        if !item.tags.contains(clean) { store.updateTags(item.tags + [clean], for: item.id) }
        newTag = ""
        isAddingTag = false
    }

    private func addCollection() {
        let clean = newCollection.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { isAddingCollection = false; return }
        store.assignCollection(clean, to: item.id)
        newCollection = ""
        isAddingCollection = false
    }
}

private struct DetailCard<Content: View>: View {
    let title: String
    let icon: String
    @ViewBuilder let content: Content

    init(title: String, icon: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.icon = icon
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(title, systemImage: icon)
                .font(.caption.weight(.semibold))
            content
        }
        .padding(13)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.background.opacity(0.48), in: RoundedRectangle(cornerRadius: 11))
        .overlay(RoundedRectangle(cornerRadius: 11).stroke(SuijiTheme.divider))
    }
}
