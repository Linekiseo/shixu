import SwiftUI

struct InboxView: View {
    @ObservedObject var store: CaptureStore
    @ObservedObject private var runtime = CaptureRuntimeController.shared

    private var sections: [CaptureTimelineEntrySection] {
        CaptureTimelineEntrySection.sections(from: store.visibleItems)
    }

    var body: some View {
        VStack(spacing: 0) {
            header

            Divider()

            VStack(spacing: 14) {
                CaptureComposerView(store: store)

                if let candidate = store.clipboardCandidate {
                    clipboardSuggestion(candidate)
                }

                if sections.isEmpty {
                    LibraryEmptyState(
                        icon: "tray.and.arrow.down",
                        title: "等待第一条真实记录",
                        description: "上方输入区只属于收件箱；也可以使用全局快捷键、截屏或系统监测随手记录。",
                        actionTitle: "打开快速记录",
                        actionIcon: "paperclip"
                    ) {
                        QuickCapturePanelController.shared.show()
                    }
                } else {
                    ScrollView {
                        LazyVStack(spacing: 18, pinnedViews: [.sectionHeaders]) {
                            ForEach(sections) { section in
                                Section {
                                    ForEach(section.entries) { entry in
                                        if let group = entry.group {
                                            CompositionTimelineCard(store: store, group: group)
                                        } else if let item = entry.item {
                                            InboxRecordCard(store: store, item: item, selected: store.selectedItemID == item.id)
                                        }
                                    }
                                } header: {
                                    TimelineSectionHeader(section: section, tint: SuijiTheme.accent)
                                }
                            }
                        }
                        .padding(.bottom, 20)
                    }
                    .scrollIndicators(.automatic)
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 18)
        }
        .navigationSplitViewColumnWidth(min: 500, ideal: 680)
    }

    private var header: some View {
        HStack(spacing: 18) {
            VStack(alignment: .leading, spacing: 2) {
                Text(store.activeTitle)
                    .font(SuijiTheme.titleFont)
                Text(store.selectedCollection == nil ? "随手放进来，之后自然找得到" : "自动整理与手动归档共同维护这个集合")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            HStack(spacing: 7) {
                Circle().fill(runtime.isCaptureEnabled ? .green : .gray).frame(width: 6, height: 6)
                Text(runtime.isCaptureEnabled ? "系统监测运行中" : "系统监测已暂停")
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 15)
    }

    private func clipboardSuggestion(_ candidate: ClipboardCandidate) -> some View {
        HStack(spacing: 10) {
            Image(systemName: candidate.kind.systemImage)
                .foregroundStyle(SuijiTheme.accent)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text("剪贴板里有新的\(candidate.kind.title)")
                    .font(.caption.weight(.semibold))
                Text(candidate.displayText)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Text("可直接拖到下方卡片上组合")
                    .font(.system(size: 9))
                    .foregroundStyle(.tertiary)
            }
            Spacer()
            Button("忽略") { store.clipboardCandidate = nil }
                .buttonStyle(.borderless)
            Button("保存") { store.capture(candidate: candidate) }
                .buttonStyle(.bordered)
        }
        .padding(10)
        .background(SuijiTheme.accent.opacity(0.045), in: RoundedRectangle(cornerRadius: 7))
        .overlay(RoundedRectangle(cornerRadius: 7).stroke(SuijiTheme.accent.opacity(0.16)))
        .contentShape(RoundedRectangle(cornerRadius: 7))
        .onDrag {
            let payload = candidate.text ?? candidate.fileURL?.absoluteString ?? candidate.displayText
            return NSItemProvider(object: payload as NSString)
        }
        .help("拖到一条记录上，智能补全或组成一组")
    }
}
