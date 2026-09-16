import SwiftUI
import UniformTypeIdentifiers

struct CaptureRow: View {
    @ObservedObject var store: CaptureStore
    let item: CaptureItem
    let selected: Bool
    var showsCompositionBadge = true
    var compactLayout = false
    @State private var isDropTarget = false
    @State private var isHovering = false

    var body: some View {
        card
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .overlay {
                if selected || isDropTarget {
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(isDropTarget ? Color.green : item.kind.tint.opacity(0.82), lineWidth: isDropTarget ? 3 : 2)
                }
            }
            .overlay(alignment: .top) {
                if showsCompositionBadge, let kind = item.compositionKind {
                    compositionBadge(kind)
                        .padding(.top, 8)
                        .allowsHitTesting(false)
                } else if isHovering {
                    Label("拖拽组合", systemImage: "circle.grid.3x3.fill")
                        .font(.system(size: 9, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 5)
                        .background(.black.opacity(0.62), in: Capsule())
                        .padding(.top, 8)
                        .allowsHitTesting(false)
                }
            }
            .shadow(color: .black.opacity(selected ? 0.1 : 0.035), radius: selected ? 12 : 5, y: 3)
            .contentShape(RoundedRectangle(cornerRadius: 14))
            .onTapGesture { store.selectedItemID = item.id }
            .onTapGesture(count: 2) { CapturePrimaryAction.perform(store: store, item: item) }
            .onHover { isHovering = $0 }
            .onDrag {
                CaptureDragProvider.make(store: store, item: item)
            }
            .onDrop(of: [.shixuCaptureRecord, .utf8PlainText, .url], isTargeted: $isDropTarget, perform: receiveDrop)
            .help("拖到另一条记录上即可智能组合")
            .contextMenu { managementMenu }
    }

    @ViewBuilder
    private var card: some View {
        CaptureCardBody(store: store, item: item, compactLayout: compactLayout)
    }

    @ViewBuilder
    private var managementMenu: some View {
        Button(item.isFavorite ? "取消收藏" : "收藏") { store.toggleFavorite(item.id) }
        Menu("整理到") {
            ForEach(store.availableCollections, id: \.self) { collection in
                Button {
                    store.assignCollection(collection, to: item.id)
                } label: {
                    if item.collection == collection {
                        Label(collection, systemImage: "checkmark")
                    } else {
                        Text(collection)
                    }
                }
            }
        }
        if item.compositionID != nil {
            Button("移出组合", systemImage: "rectangle.portrait.and.arrow.right") {
                store.removeFromComposition(item.id)
            }
        }
        Divider()
        if item.isDeleted {
            Button("恢复") { store.restore(item.id) }
            Button("永久删除", role: .destructive) { store.deletePermanently(item.id) }
        } else {
            Button("移到回收站", role: .destructive) { store.moveToTrash(item.id) }
        }
    }

    private func compositionBadge(_ kind: CaptureCompositionKind) -> some View {
        let count = store.compositionMembers(for: item).count
        return Label("\(kind.title) · \(count)", systemImage: kind.systemImage)
            .font(.system(size: 9, weight: .semibold, design: .rounded))
            .foregroundStyle(.white)
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(.black.opacity(0.68), in: Capsule())
    }

    private func receiveDrop(_ providers: [NSItemProvider]) -> Bool {
        let targetID = item.id
        if let provider = providers.first(where: {
            $0.hasItemConformingToTypeIdentifier(UTType.shixuCaptureRecord.identifier)
        }) {
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
                    Task { @MainActor in
                        _ = store.handleDroppedURL(url, onto: targetID)
                    }
                }
                return true
            }
            if provider.canLoadObject(ofClass: NSString.self) {
                provider.loadObject(ofClass: NSString.self) { object, _ in
                    guard let text = object as? String else { return }
                    Task { @MainActor in
                        _ = store.handleDroppedText(text, onto: targetID)
                    }
                }
                return true
            }
        }
        return false
    }
}

/// 只负责记录本身的类型化呈现；选中、组合和拖放由外层场景各自管理。
/// “全部记录”的瀑布流与组合成员因此可以共享完整信息，但不会和收件箱横条布局互相影响。
struct CaptureCardBody: View {
    @ObservedObject var store: CaptureStore
    let item: CaptureItem
    var compactLayout = false

    @ViewBuilder
    var body: some View {
        switch item.kind {
        case .text:
            TextNoteCard(store: store, item: item, compactLayout: compactLayout)
        case .image:
            ImageMomentCard(store: store, item: item, compactLayout: compactLayout)
        case .web:
            WebBookmarkCard(store: store, item: item, compactLayout: compactLayout)
        case .credential:
            CredentialVaultCard(store: store, item: item, compactLayout: compactLayout)
        case .file:
            FileReferenceCard(store: store, item: item, compactLayout: compactLayout)
        }
    }
}
