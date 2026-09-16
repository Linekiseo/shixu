import AppKit
import SwiftUI

struct WebLibraryView: View {
    @ObservedObject var store: CaptureStore
    private let columns = [GridItem(.adaptive(minimum: 280, maximum: 380), spacing: 16)]

    private var pages: [CaptureItem] {
        store.items.filter { !$0.isDeleted && $0.kind == .web }.sorted { $0.createdAt > $1.createdAt }
    }

    private var sections: [CaptureTimelineSection] {
        CaptureTimelineSection.sections(from: pages)
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()

            if sections.isEmpty {
                LibraryEmptyState(
                    icon: "globe",
                    title: "还没有网页记录",
                    description: "复制网页地址或通过 macOS 服务存入\(AppBrand.displayName)，页面会按保存日期排列。",
                    actionTitle: "粘贴网页",
                    actionIcon: "link.badge.plus",
                    action: pasteWeb
                )
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 22, pinnedViews: [.sectionHeaders]) {
                        ForEach(sections) { section in
                            Section {
                                LazyVGrid(columns: columns, alignment: .leading, spacing: 16) {
                                    ForEach(section.items) { item in
                                        WebLibraryCard(store: store, item: item, selected: store.selectedItemID == item.id)
                                    }
                                }
                            } header: {
                                TimelineSectionHeader(section: section, tint: .blue)
                            }
                        }
                    }
                    .padding(20)
                }
            }
        }
        .navigationSplitViewColumnWidth(min: 520, ideal: 720)
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text("网页资料").font(SuijiTheme.titleFont)
                Text("保存链接时自动压缩归档；需要账号的站点登录一次即可复用")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Label("本机离线存档", systemImage: "archivebox.fill")
                .font(.caption2)
                .foregroundStyle(.secondary)
            Button("粘贴网页", systemImage: "link.badge.plus", action: pasteWeb)
            .buttonStyle(.bordered)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 15)
    }

    private func pasteWeb() {
        if let value = NSPasteboard.general.string(forType: .string) {
            store.capture(text: value, forcedKind: .web, source: "网页资料库")
        }
    }
}

private struct WebLibraryCard: View {
    @ObservedObject var store: CaptureStore
    let item: CaptureItem
    let selected: Bool
    @State private var isShowingOfflineArchive = false
    @State private var isShowingWebsiteSession = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let url = URL(string: item.body) {
                Button {
                    if item.webArchiveState == .archived, store.webArchiveURL(for: item) != nil {
                        isShowingOfflineArchive = true
                    } else {
                        store.selectedItemID = item.id
                    }
                } label: {
                    WebArtworkPreview(url: url, localArchive: item.webArchivePreviewSource)
                        .frame(height: 144)
                        .clipShape(RoundedRectangle(cornerRadius: 9))
                }
                .buttonStyle(.plain)
                .help(item.webArchiveState == .archived ? "打开保存在本机的网页快照" : "选择这条网页记录")
            }

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(item.domain ?? "网页")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.blue)
                    Spacer()
                    Text(item.createdAt.suijiDayLabel)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                Text(item.title)
                    .font(.custom("Songti SC", size: 16).weight(.semibold))
                    .lineLimit(2)
                Text(item.summary.isEmpty ? "已保存网页地址，可打开完整页面。" : item.summary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
            }

            HStack {
                WebArchiveStatusBadge(item: item)
                Spacer()
                if item.webArchiveState == .archived, store.webArchiveURL(for: item) != nil {
                    Button("查看离线快照", systemImage: "archivebox.fill") { isShowingOfflineArchive = true }
                        .buttonStyle(.borderless)
                        .font(.caption)
                } else if item.webArchiveState == .loginRequired {
                    Button("登录归档", systemImage: "person.badge.key") { isShowingWebsiteSession = true }
                        .buttonStyle(.borderless)
                        .font(.caption)
                } else if item.webArchiveState != .capturing {
                    Button("备份", systemImage: "archivebox") {
                        store.requestWebArchive(for: item.id)
                    }
                        .buttonStyle(.borderless)
                        .font(.caption)
                }
                Button("打开", systemImage: "arrow.up.right") {
                    if let url = URL(string: item.body) { NSWorkspace.shared.open(url) }
                }
                .buttonStyle(.borderless)
                .font(.caption)
            }
        }
        .padding(12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 13))
        .overlay {
            RoundedRectangle(cornerRadius: 13)
                .stroke(selected ? Color.blue.opacity(0.75) : SuijiTheme.divider, lineWidth: selected ? 1.5 : 1)
        }
        .overlay(alignment: .topTrailing) {
            CompositionMembershipPill(store: store, item: item)
        }
        .contentShape(Rectangle())
        .onTapGesture { store.selectedItemID = item.id }
        .sheet(isPresented: $isShowingOfflineArchive) {
            if let archiveURL = store.webArchiveURL(for: item), let liveURL = URL(string: item.body) {
                OfflineWebArchiveSheet(archiveURL: archiveURL, liveURL: liveURL, item: item)
            }
        }
        .sheet(isPresented: $isShowingWebsiteSession) {
            WebsiteSessionArchiveSheet(store: store, item: item)
        }
        .contextMenu {
            if item.webArchiveState == .archived {
                Button("查看离线存档") { isShowingOfflineArchive = true }
                Button("登录站点并更新存档") { isShowingWebsiteSession = true }
            } else if item.webArchiveState == .loginRequired {
                Button("登录站点并归档") { isShowingWebsiteSession = true }
            } else {
                Button("创建网页备份") { store.requestWebArchive(for: item.id) }
            }
            Divider()
            Button(item.isFavorite ? "取消收藏" : "收藏") { store.toggleFavorite(item.id) }
            Button("移到回收站", role: .destructive) { store.moveToTrash(item.id) }
        }
    }
}
