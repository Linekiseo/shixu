import SwiftUI

struct TimelineBrowseView: View {
    @ObservedObject var store: CaptureStore
    @State private var isSelectingTrash = false
    @State private var trashSelection: Set<CaptureItem.ID> = []
    @State private var isConfirmingPermanentDelete = false

    private var sections: [CaptureTimelineEntrySection] {
        CaptureTimelineEntrySection.sections(from: store.visibleItems)
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()

            if sections.isEmpty {
                emptyState
            } else {
                ScrollView {
                    LazyVStack(spacing: 20, pinnedViews: [.sectionHeaders]) {
                        ForEach(sections) { section in
                            Section {
                                ForEach(section.entries) { entry in
                                    timelineEntry(entry)
                                }
                            } header: {
                                TimelineSectionHeader(section: section, tint: headerTint)
                            }
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.vertical, 14)
                }
            }
        }
        .onChange(of: store.category) { _, category in
            if category != .trash { endTrashSelection() }
        }
        .onChange(of: store.visibleItems.map(\.id)) { _, visibleIDs in
            trashSelection.formIntersection(visibleIDs)
            if store.category == .trash, visibleIDs.isEmpty { endTrashSelection() }
        }
        .alert("永久删除 \(trashSelection.count) 条记录？", isPresented: $isConfirmingPermanentDelete) {
            Button("取消", role: .cancel) {}
            Button("永久删除", role: .destructive) {
                store.deletePermanently(trashSelection)
                endTrashSelection()
            }
        } message: {
            Text("所选内容及其本机附件、压缩备份和网页存档将无法恢复。")
        }
    }

    private var header: some View {
        HStack(spacing: 18) {
            VStack(alignment: .leading, spacing: 3) {
                Text(pageTitle)
                    .font(SuijiTheme.titleFont)
                Text(pageSubtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Label("\(store.visibleItems.count) 条记录", systemImage: "clock.arrow.circlepath")
                .font(.caption2)
                .foregroundStyle(.secondary)
            if store.category == .trash {
                trashActions
            } else {
                Button("快速记录", systemImage: "plus") {
                    QuickCapturePanelController.shared.show()
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 15)
    }

    private var pageTitle: String {
        if let collection = store.selectedCollection { return collection }
        switch store.category {
        case .all: return "全部记录"
        case .compositions: return "内容组合"
        case .favorites: return "收藏"
        case .trash: return "回收站"
        default: return store.activeTitle
        }
    }

    private var pageSubtitle: String {
        if store.selectedCollection != nil { return "按照捕获时间回看这个集合，整理结果不会改变原始记录时间" }
        switch store.category {
        case .all: return "所有真实记录按时间展开，不显示收集输入区"
        case .compositions: return "相关记录以共同容器呈现"
        case .favorites: return "重要内容仍保留在原时间位置，便于回到当时的上下文"
        case .trash: return "选择多条记录后，可以批量恢复或永久删除"
        default: return "按照捕获时间回看内容"
        }
    }

    @ViewBuilder
    private func timelineEntry(_ entry: CaptureTimelineEntry) -> some View {
        if let group = entry.group {
            CompositionTimelineCard(store: store, group: group)
        } else if let item = entry.item {
            if store.category == .trash, isSelectingTrash {
                TrashSelectableRow(
                    store: store,
                    item: item,
                    isSelected: trashSelection.contains(item.id)
                ) {
                    if trashSelection.contains(item.id) {
                        trashSelection.remove(item.id)
                    } else {
                        trashSelection.insert(item.id)
                    }
                }
            } else {
                CaptureRow(
                    store: store,
                    item: item,
                    selected: store.selectedItemID == item.id
                )
            }
        }
    }

    @ViewBuilder
    private var trashActions: some View {
        if isSelectingTrash {
            Button(trashSelection.count == store.visibleItems.count ? "取消全选" : "全选") {
                if trashSelection.count == store.visibleItems.count {
                    trashSelection.removeAll()
                } else {
                    trashSelection = Set(store.visibleItems.map(\.id))
                }
            }
            .buttonStyle(.bordered)

            Button("恢复 \(trashSelection.count)", systemImage: "arrow.uturn.backward") {
                store.restore(trashSelection)
                endTrashSelection()
            }
            .buttonStyle(.bordered)
            .disabled(trashSelection.isEmpty)

            Button("永久删除 \(trashSelection.count)", systemImage: "trash.fill", role: .destructive) {
                isConfirmingPermanentDelete = true
            }
            .buttonStyle(.borderedProminent)
            .tint(.red)
            .disabled(trashSelection.isEmpty)

            Button("完成") { endTrashSelection() }
                .buttonStyle(.bordered)
        } else {
            Button("选择", systemImage: "checkmark.circle") {
                isSelectingTrash = true
            }
            .buttonStyle(.bordered)
        }
    }

    private func endTrashSelection() {
        isSelectingTrash = false
        trashSelection.removeAll()
        isConfirmingPermanentDelete = false
    }

    private var headerTint: Color {
        switch store.category {
        case .favorites: .yellow
        case .trash: .secondary
        default: SuijiTheme.accent
        }
    }

    private var emptyState: some View {
        Group {
            switch store.category {
            case .favorites:
                LibraryEmptyState(
                    icon: "star",
                    title: "还没有收藏",
                    description: "在任意卡片上点按星标，内容会保持原时间并汇集到这里。"
                )
            case .trash:
                LibraryEmptyState(
                    icon: "trash",
                    title: "回收站是空的",
                    description: "移除的内容会保留在这里，永久删除前仍可以恢复。"
                )
            default:
                LibraryEmptyState(
                    icon: store.selectedCollection == nil ? "clock" : "square.stack.3d.up",
                    title: store.selectedCollection == nil ? "还没有真实记录" : "这个集合还是空的",
                    description: "新的文字、截图、网页和文件会按照记录时间出现在这里。",
                    actionTitle: "快速记录",
                    actionIcon: "paperclip"
                ) {
                    QuickCapturePanelController.shared.show()
                }
            }
        }
    }
}

private struct TrashSelectableRow: View {
    @ObservedObject var store: CaptureStore
    let item: CaptureItem
    let isSelected: Bool
    let toggle: () -> Void

    var body: some View {
        CaptureRow(store: store, item: item, selected: isSelected)
            .allowsHitTesting(false)
            .overlay(alignment: .topLeading) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                    .padding(12)
                    .background(.regularMaterial, in: Circle())
                    .padding(6)
            }
            .contentShape(RoundedRectangle(cornerRadius: 14))
            .onTapGesture(perform: toggle)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(item.title)，\(isSelected ? "已选择" : "未选择")")
            .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
