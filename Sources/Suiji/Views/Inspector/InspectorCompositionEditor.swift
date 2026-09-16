import SwiftUI
import UniformTypeIdentifiers

struct InspectorCompositionEditor: View {
    @ObservedObject var store: CaptureStore
    let item: CaptureItem
    @State private var previewOrder: [CaptureItem.ID] = []
    @State private var draggingMemberID: CaptureItem.ID?
    @State private var insertionMemberID: CaptureItem.ID?
    @State private var isDropTarget = false

    private var sourceMembers: [CaptureItem] { store.compositionMembers(for: item) }
    private var members: [CaptureItem] {
        guard !previewOrder.isEmpty else { return sourceMembers }
        let lookup = Dictionary(uniqueKeysWithValues: sourceMembers.map { ($0.id, $0) })
        return previewOrder.compactMap { lookup[$0] } + sourceMembers.filter { !previewOrder.contains($0.id) }
    }
    private var kind: CaptureCompositionKind { item.compositionKind ?? .related }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: kind.systemImage)
                    .font(.headline).foregroundStyle(kind.tint)
                    .frame(width: 36, height: 36)
                    .background(kind.tint.opacity(0.13), in: RoundedRectangle(cornerRadius: 10))
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.compositionTitle ?? kind.title).font(.headline).lineLimit(1)
                    Text(isDropTarget && draggingMemberID == nil ? "松开加入组合" : "可继续拖入卡片，组内拖动调整顺序")
                        .font(.caption2).foregroundStyle(.secondary)
                }
                Spacer()
            }

            ForEach(Array(members.enumerated()), id: \.element.id) { index, member in
                if draggingMemberID != nil, insertionMemberID == member.id {
                    HStack(spacing: 8) {
                        Capsule().fill(kind.tint.gradient).frame(height: 3)
                        Text("放到第 \(index + 1) 位")
                            .font(.system(size: 9, weight: .bold, design: .rounded))
                            .foregroundStyle(kind.tint)
                        Capsule().fill(kind.tint.gradient).frame(height: 3)
                    }
                    .transition(.scale.combined(with: .opacity))
                }
                memberRow(member, index: index)
                    .scaleEffect(draggingMemberID == member.id ? 0.98 : 1)
                    .opacity(draggingMemberID == member.id ? 0.58 : 1)
            }

            HStack {
                Button("查看组合资料库", systemImage: "square.stack.3d.up.fill") {
                    store.selectCategory(.compositions, selecting: item.id)
                }.buttonStyle(.borderedProminent).tint(kind.tint).controlSize(.small)
                Spacer()
                Button("移出当前记录", systemImage: "rectangle.portrait.and.arrow.right") {
                    store.removeFromComposition(item.id)
                }.buttonStyle(.borderless).controlSize(.small)
            }
        }
        .padding(14)
        .background(LinearGradient(colors: [kind.tint.opacity(0.12), kind.tint.opacity(0.03)], startPoint: .topLeading, endPoint: .bottomTrailing), in: RoundedRectangle(cornerRadius: 13))
        .overlay(RoundedRectangle(cornerRadius: 13).stroke(kind.tint.opacity(isDropTarget ? 1 : 0.38), lineWidth: isDropTarget ? 3 : 1.5).allowsHitTesting(false))
        .contentShape(RoundedRectangle(cornerRadius: 13))
        .onDrop(of: [.shixuCaptureRecord], delegate: dropDelegate(before: nil))
        .animation(.snappy(duration: 0.22, extraBounce: 0.08), value: previewOrder)
        .onAppear { previewOrder = sourceMembers.map(\.id) }
        .onChange(of: sourceMembers.map(\.id)) { _, ids in
            guard draggingMemberID == nil else { return }
            previewOrder = ids
        }
    }

    private func memberRow(_ member: CaptureItem, index: Int) -> some View {
        let current = member.id == item.id
        return HStack(spacing: 7) {
            Image(systemName: "line.3.horizontal")
                .foregroundStyle(.secondary)
                .frame(width: 18, height: 30)
                .contentShape(Rectangle())
                .help("拖动调整组合顺序")
            Text(String(format: "%02d", index + 1))
                .font(.caption2.monospacedDigit().weight(.bold)).foregroundStyle(kind.tint).frame(width: 24)
            Button {
                store.selectedItemID = member.id
            } label: {
                HStack(spacing: 7) {
                    Image(systemName: member.kind.systemImage).foregroundStyle(member.kind.tint)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(member.title).lineLimit(1)
                        Text(member.compositionDisplayRole).font(.caption2).foregroundStyle(.secondary)
                    }
                    Spacer()
                    if current { Text("当前").font(.caption2).foregroundStyle(kind.tint) }
                }
            }
            .buttonStyle(.plain)
        }
        .font(.caption)
        .padding(.horizontal, 8).padding(.vertical, 5)
        .background(current ? kind.tint.opacity(0.1) : Color.primary.opacity(0.025), in: RoundedRectangle(cornerRadius: 9))
        .overlay(RoundedRectangle(cornerRadius: 9).stroke(current ? kind.tint.opacity(0.35) : SuijiTheme.divider))
        .onDrag {
            previewOrder = sourceMembers.map(\.id)
            draggingMemberID = member.id
            insertionMemberID = member.id
            return CaptureDragProvider.make(store: store, item: member)
        } preview: {
            Label(member.title, systemImage: member.kind.systemImage)
                .font(.caption.weight(.semibold))
                .lineLimit(1)
                .padding(10)
                .frame(width: 180, alignment: .leading)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(kind.tint.opacity(0.6)))
        }
        .onDrop(of: [.shixuCaptureRecord], delegate: dropDelegate(before: member.id))
    }

    private func dropDelegate(before destinationID: CaptureItem.ID?) -> CompositionRecordDropDelegate {
        CompositionRecordDropDelegate(
            destinationID: destinationID,
            compositionID: item.compositionID,
            store: store,
            previewOrder: $previewOrder,
            draggingMemberID: $draggingMemberID,
            insertionMemberID: $insertionMemberID,
            isDropTarget: $isDropTarget
        )
    }
}
