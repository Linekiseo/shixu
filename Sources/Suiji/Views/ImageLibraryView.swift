import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct ImageLibraryView: View {
    @ObservedObject var store: CaptureStore

    private var images: [CaptureItem] {
        store.items.filter { !$0.isDeleted && $0.kind == .image }.sorted { $0.createdAt > $1.createdAt }
    }

    private var sections: [CaptureTimelineSection] {
        CaptureTimelineSection.sections(from: images)
    }

    private let columns = [GridItem(.adaptive(minimum: 220, maximum: 310), spacing: 16)]

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()

            if sections.isEmpty {
                LibraryEmptyState(
                    icon: "photo.on.rectangle",
                    title: "还没有图片记录",
                    description: "截屏、粘贴图片或链接本地照片后，会按捕获日期形成画面时间线。",
                    actionTitle: "添加图片",
                    actionIcon: "photo.badge.plus",
                    action: chooseImages
                )
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 22, pinnedViews: [.sectionHeaders]) {
                        ForEach(sections) { section in
                            Section {
                                LazyVGrid(columns: columns, alignment: .leading, spacing: 16) {
                                    ForEach(section.items) { item in
                                        ImageMomentCard(store: store, item: item)
                                            .overlay {
                                                if store.selectedItemID == item.id {
                                                    RoundedRectangle(cornerRadius: 14)
                                                        .stroke(Color.orange, lineWidth: 2)
                                                }
                                            }
                                            .overlay(alignment: .topTrailing) {
                                                CompositionMembershipPill(store: store, item: item)
                                            }
                                            .contentShape(RoundedRectangle(cornerRadius: 14))
                                            .onTapGesture { store.selectedItemID = item.id }
                                    }
                                }
                            } header: {
                                TimelineSectionHeader(section: section, tint: .orange)
                            }
                        }
                    }
                    .padding(20)
                }
            }
        }
        .navigationSplitViewColumnWidth(min: 500, ideal: 680)
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text("图片与截图").font(SuijiTheme.titleFont)
                Text("按画面浏览；原图仍保留在原位置或剪贴板资料区")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("截屏", systemImage: "viewfinder") {
                ScreenshotService.shared.captureInteractive { store.importCurrentClipboard() }
            }
            .buttonStyle(.bordered)
            Button("添加图片", systemImage: "plus") { chooseImages() }
                .buttonStyle(.bordered)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 15)
    }

    private func chooseImages() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = true
        if panel.runModal() == .OK {
            panel.urls.forEach { store.capture(fileURL: $0, source: "图片资料库") }
        }
    }
}
