import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct CompactRecordCard: View {
    @ObservedObject var store: CaptureStore
    let item: CaptureItem
    @State private var isDropTarget = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            artwork.frame(height: 112).clipped()
            VStack(alignment: .leading, spacing: 7) {
                HStack(spacing: 6) {
                    Label(item.kind.cardLabel, systemImage: item.kind.systemImage)
                        .foregroundStyle(item.kind.tint)
                    Spacer()
                    Text(item.createdAt.suijiTime).monospacedDigit().foregroundStyle(.tertiary)
                }
                .font(.system(size: 9, weight: .semibold))
                Text(item.title)
                    .font(.custom("Songti SC", size: 15).weight(.semibold))
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                HStack(spacing: 6) {
                    if let app = item.sourceApplication {
                        Label(app, systemImage: "app.badge")
                    } else {
                        Label(item.collection ?? item.source, systemImage: "tray")
                    }
                    Spacer()
                    if item.compositionID != nil { Image(systemName: "square.stack.3d.up.fill") }
                    if item.isFavorite { Image(systemName: "star.fill").foregroundStyle(.yellow) }
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            }
            .padding(11)
        }
        .frame(minHeight: 205, maxHeight: 205)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(
            isDropTarget ? Color.green : (store.selectedItemID == item.id ? item.kind.tint : SuijiTheme.divider),
            lineWidth: isDropTarget ? 3 : (store.selectedItemID == item.id ? 2 : 1)
        ))
        .contentShape(RoundedRectangle(cornerRadius: 14))
        .onTapGesture { store.selectedItemID = item.id }
        .onTapGesture(count: 2) { CapturePrimaryAction.perform(store: store, item: item) }
        .onDrag { CaptureDragProvider.make(store: store, item: item) }
        .onDrop(of: [.shixuCaptureRecord, .utf8PlainText, .url], isTargeted: $isDropTarget, perform: receiveDrop)
        .contextMenu {
            Button("打开", systemImage: "arrow.up.forward.app") { CapturePrimaryAction.perform(store: store, item: item) }
            Button("预览", systemImage: "eye") { CapturePrimaryAction.preview(store: store, item: item) }
                .disabled(store.attachmentURL(for: item) == nil)
            Divider()
            Button(item.isFavorite ? "取消收藏" : "收藏") { store.toggleFavorite(item.id) }
            Button("移到回收站", role: .destructive) { store.moveToTrash(item.id) }
        }
        .help("单击查看详情 · 双击打开 · 拖拽可组合或导出")
    }

    @ViewBuilder private var artwork: some View {
        switch item.kind {
        case .image:
            if let url = store.attachmentURL(for: item), let image = NSImage(contentsOf: url) {
                Image(nsImage: image).resizable().scaledToFill()
            } else { kindPlaceholder(icon: "photo", tint: .orange) }
        case .web:
            if let url = URL(string: item.body) {
                WebArtworkPreview(url: url, localArchive: item.webArchivePreviewSource).allowsHitTesting(false)
            } else { kindPlaceholder(icon: "globe", tint: .blue) }
        case .file:
            if let url = store.attachmentURL(for: item) {
                FileThumbnailPreview(url: url, fallbackExtension: item.fileExtension).allowsHitTesting(false)
            } else { kindPlaceholder(icon: "doc", tint: .teal) }
        case .credential:
            ZStack {
                LinearGradient(colors: [.indigo.opacity(0.18), .purple.opacity(0.05)], startPoint: .topLeading, endPoint: .bottomTrailing)
                HStack(spacing: 13) {
                    CredentialPlatformMark(platform: item.platform, credentialType: item.credentialType ?? .account, size: 48)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(item.platform ?? "安全凭据").font(.headline)
                        Text(item.username ?? "••••••••").font(.caption.monospaced()).foregroundStyle(.secondary)
                    }
                }
            }
        case .text:
            ZStack(alignment: .topLeading) {
                LinearGradient(colors: [.indigo.opacity(0.12), Color(nsColor: .textBackgroundColor).opacity(0.75)], startPoint: .topLeading, endPoint: .bottomTrailing)
                Text(item.body.isEmpty ? item.title : item.body)
                    .font(item.textFormat == nil ? .custom("Songti SC", size: 13) : .system(size: 10, design: .monospaced))
                    .lineSpacing(4).lineLimit(6).padding(13)
            }
        }
    }

    private func kindPlaceholder(icon: String, tint: Color) -> some View {
        ZStack {
            tint.opacity(0.09)
            Image(systemName: icon).font(.system(size: 34, weight: .light)).foregroundStyle(tint)
        }
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

struct CompactCompositionCard: View {
    @ObservedObject var store: CaptureStore
    let group: CaptureCompositionGroup
    @State private var isExpanded = true
    @State private var isDropTarget = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 9) {
                Image(systemName: group.kind.systemImage)
                    .foregroundStyle(group.kind.tint)
                    .frame(width: 32, height: 32)
                    .background(group.kind.tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 9))
                VStack(alignment: .leading, spacing: 2) {
                    Text(group.title).font(.headline).lineLimit(1)
                    Text("明确组合 · \(group.members.count) 项 · 可拖拽排序").font(.caption2).foregroundStyle(.secondary)
                }
                Spacer()
                Button { withAnimation(.snappy) { isExpanded.toggle() } } label: {
                    Image(systemName: isExpanded ? "chevron.up.circle.fill" : "chevron.down.circle.fill")
                }.buttonStyle(.plain).foregroundStyle(group.kind.tint)
            }
            if isExpanded {
                ForEach(Array(group.members.enumerated()), id: \.element.id) { index, member in
                    HStack(spacing: 7) {
                        Image(systemName: "line.3.horizontal").foregroundStyle(.tertiary)
                        Text("\(index + 1)").font(.caption2.monospacedDigit()).foregroundStyle(group.kind.tint).frame(width: 18)
                        Button { store.selectedItemID = member.id } label: {
                            Label(member.title, systemImage: member.kind.systemImage).lineLimit(1).frame(maxWidth: .infinity, alignment: .leading)
                        }.buttonStyle(.plain)
                        Button { store.shiftCompositionMember(member.id, in: group.id, by: -1) } label: { Image(systemName: "arrow.up") }
                            .disabled(index == 0)
                        Button { store.shiftCompositionMember(member.id, in: group.id, by: 1) } label: { Image(systemName: "arrow.down") }
                            .disabled(index == group.members.count - 1)
                    }
                    .font(.caption)
                    .padding(.vertical, 4)
                    .onDrag { CaptureDragProvider.make(store: store, item: member) }
                    .onDrop(of: [.shixuCaptureRecord], isTargeted: nil) { providers in
                        CompositionDropHandler.receive(providers, store: store, compositionID: group.id, before: member.id)
                    }
                }
            } else {
                Text(group.members.map(\.title).prefix(3).joined(separator: " · ")).font(.caption).foregroundStyle(.secondary).lineLimit(2)
            }
        }
        .padding(13)
        .frame(minHeight: 205, alignment: .top)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(group.kind.tint.opacity(isDropTarget ? 1 : 0.48), lineWidth: isDropTarget ? 3 : 1.5).allowsHitTesting(false))
        .contentShape(RoundedRectangle(cornerRadius: 14))
        .onDrop(of: [.shixuCaptureRecord], isTargeted: $isDropTarget) { providers in
            CompositionDropHandler.receive(providers, store: store, compositionID: group.id)
        }
    }
}
