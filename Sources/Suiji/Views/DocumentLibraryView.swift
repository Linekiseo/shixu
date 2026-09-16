import AppKit
import SwiftUI

struct DocumentLibraryView: View {
    @ObservedObject var store: CaptureStore
    @AppStorage("fileStorageMode") private var fileStorageMode = FileStorageMode.linked.rawValue
    @State private var scope: DocumentScope = .all
    private let columns = [GridItem(.adaptive(minimum: 240, maximum: 330), spacing: 16)]

    private var documents: [CaptureItem] {
        store.items
            .filter { !$0.isDeleted && ($0.kind == .file || $0.textFormat != nil) }
            .filter(scope.includes)
            .sorted { $0.createdAt > $1.createdAt }
    }

    private var sections: [CaptureTimelineSection] {
        CaptureTimelineSection.sections(from: documents)
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()

            if sections.isEmpty {
                LibraryEmptyState(
                    icon: "doc.on.doc",
                    title: scope == .all ? "还没有文件记录" : "这个范围没有文件",
                    description: scope == .all ? "链接本地文件后，会按首次记录日期形成文件时间线。" : "切换到全部范围，或添加新的本地文件引用。",
                    actionTitle: scope == .all ? "添加文件" : "查看全部",
                    actionIcon: scope == .all ? "doc.badge.plus" : "line.3.horizontal.decrease.circle"
                ) {
                    if scope == .all { chooseFiles() }
                    else { scope = .all }
                }
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 22, pinnedViews: [.sectionHeaders]) {
                        ForEach(sections) { section in
                            Section {
                                LazyVGrid(columns: columns, alignment: .leading, spacing: 16) {
                                    ForEach(section.items) { item in
                                        DocumentLibraryCard(store: store, item: item, selected: store.selectedItemID == item.id)
                                    }
                                }
                            } header: {
                                TimelineSectionHeader(section: section, tint: .teal)
                            }
                        }
                    }
                    .padding(20)
                }
            }

            footer
        }
        .navigationSplitViewColumnWidth(min: 560, ideal: 740)
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text("文档库").font(SuijiTheme.titleFont)
                Text("统一预览外部文件引用与由粘贴内容生成的格式文件")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Picker("范围", selection: $scope) {
                ForEach(DocumentScope.allCases) { scope in Text(scope.title).tag(scope) }
            }
            .labelsHidden()
            .pickerStyle(.segmented)
            .frame(width: 340)
            Button("添加文件", systemImage: "plus") { chooseFiles() }
                .buttonStyle(.bordered)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 15)
    }

    private var footer: some View {
        HStack(spacing: 8) {
            Image(systemName: "internaldrive")
            if let mode = FileStorageMode(rawValue: fileStorageMode) {
                Text("当前策略：\(mode.title)")
            }
            Spacer()
            Text("\(documents.count) 个文档")
        }
        .font(.caption2)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 16)
        .frame(height: 34)
        .background(.bar)
    }

    private func chooseFiles() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        if panel.runModal() == .OK {
            panel.urls.forEach { store.capture(fileURL: $0, source: "文档库") }
        }
    }
}

private struct DocumentLibraryCard: View {
    @ObservedObject var store: CaptureStore
    let item: CaptureItem
    let selected: Bool
    @State private var isShowingPreview = false

    private var url: URL? { store.attachmentURL(for: item) }
    private var format: FileFormatDescriptor { .describe(url: url, fallbackExtension: item.fileExtension) }

    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            preview

            HStack(alignment: .top, spacing: 10) {
                FileTypeIcon(url: url, fallbackExtension: item.fileExtension, size: 34)
                VStack(alignment: .leading, spacing: 4) {
                    Text(item.title)
                        .font(.custom("Songti SC", size: 15).weight(.semibold))
                        .lineLimit(2)
                    Text(metadataLine)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }

            HStack {
                Label(statusTitle, systemImage: statusIcon)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(url == nil ? SuijiTheme.accent : .green)
                Spacer()
                if let collection = item.collection {
                    Text(collection)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Button("预览", systemImage: "eye") {
                    guard let url else { return }
                    PreviewWindowController.shared.showFile(url: url, item: item)
                }
                    .buttonStyle(.borderless)
                    .foregroundStyle(.teal)
                    .font(.caption2)
                    .disabled(url == nil)
            }
        }
        .padding(12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 13))
        .overlay {
            RoundedRectangle(cornerRadius: 13)
                .stroke(selected ? Color.teal.opacity(0.75) : SuijiTheme.divider, lineWidth: selected ? 1.5 : 1)
        }
        .overlay(alignment: .topTrailing) {
            CompositionMembershipPill(store: store, item: item)
        }
        .contentShape(Rectangle())
        .onTapGesture { store.selectedItemID = item.id }
        .onTapGesture(count: 2) { if let url { NSWorkspace.shared.open(url) } }
        .onDrag { CaptureDragProvider.make(store: store, item: item) }
        .help("拖出即可在其他 App 中使用原文件")
        .contextMenu {
            Button("打开") { if let url { NSWorkspace.shared.open(url) } }
                .disabled(url == nil)
            Button("在访达显示") {
                let target = FileReferenceService.resolve(bookmark: item.fileBookmark, fallbackPath: item.originalLocation) ?? url
                if let target { NSWorkspace.shared.activateFileViewerSelecting([target]) }
            }
            .disabled(url == nil)
            Divider()
            Button(item.isFavorite ? "取消收藏" : "收藏") { store.toggleFavorite(item.id) }
            Button("移到回收站", role: .destructive) { store.moveToTrash(item.id) }
        }
    }

    @ViewBuilder
    private var preview: some View {
        if let url {
            ZStack(alignment: .topLeading) {
                if item.textFormat != nil {
                    GeneratedTextThumbnail(item: item)
                } else {
                    FileThumbnailPreview(url: url, fallbackExtension: item.fileExtension)
                        .allowsHitTesting(false)
                }
                Label(format.category, systemImage: format.systemImage)
                    .font(.caption2.weight(.semibold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(.regularMaterial, in: Capsule())
                    .padding(8)
            }
            .frame(height: 126)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(SuijiTheme.divider))
        } else {
            VStack(spacing: 8) {
                FileTypeIcon(url: nil, fallbackExtension: item.fileExtension, size: 48)
                Text("原文件暂时不可用")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, minHeight: 126)
            .background(.quaternary.opacity(0.16), in: RoundedRectangle(cornerRadius: 8))
        }
    }

    private var metadataLine: String {
        "\(format.formatName) · \(CaptureInsightService.byteCount(item.fileSize ?? item.backupOriginalSize)) · \(item.createdAt.suijiDayLabel)"
    }

    private var statusTitle: String {
        if url == nil { return item.backupPath == nil ? "连接失效" : "可从备份恢复" }
        if item.textFormat != nil { return "由粘贴内容生成" }
        return item.backupPath == nil ? "原文件已连接" : "已连接并备份"
    }

    private var statusIcon: String {
        if url == nil { return "exclamationmark.triangle.fill" }
        if let format = item.textFormat { return format.systemImage }
        return item.backupPath == nil ? "link" : "archivebox.fill"
    }
}

private enum DocumentScope: String, CaseIterable, Identifiable {
    case all
    case generated
    case linked
    case backedUp
    case unavailable

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: "全部"
        case .generated: "粘贴生成"
        case .linked: "仅引用"
        case .backedUp: "有备份"
        case .unavailable: "失联"
        }
    }

    func includes(_ item: CaptureItem) -> Bool {
        switch self {
        case .all:
            true
        case .generated:
            item.textFormat != nil
        case .linked:
            item.backupPath == nil && item.textFormat == nil
        case .backedUp:
            item.backupPath != nil
        case .unavailable:
            item.textFormat == nil
                && FileReferenceService.resolve(bookmark: item.fileBookmark, fallbackPath: item.originalLocation) == nil
                && item.backupPath == nil
        }
    }
}
