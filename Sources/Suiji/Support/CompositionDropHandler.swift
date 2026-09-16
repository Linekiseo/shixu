import AppKit
import SwiftUI
import UniformTypeIdentifiers

@MainActor
enum CompositionDropHandler {
    @discardableResult
    static func receive(
        _ providers: [NSItemProvider],
        store: CaptureStore,
        compositionID: UUID,
        before destinationID: UUID? = nil,
        previewOrder: [UUID] = [],
        previewSourceID: UUID? = nil,
        completion: @escaping @MainActor (Bool) -> Void = { _ in }
    ) -> Bool {
        let records = providers.filter {
            $0.hasItemConformingToTypeIdentifier(UTType.shixuCaptureRecord.identifier)
        }
        guard !records.isEmpty else { return false }

        var recordIDs = [UUID?](repeating: nil, count: records.count)
        var pending = records.count
        // Start every load before performDrop returns; macOS revokes payload access afterwards.
        // Commit only after all loads finish, preserving drag order even if callbacks arrive out of order.
        for (index, provider) in records.enumerated() {
            CaptureDragProvider.loadRecordID(from: provider) { sourceID in
                recordIDs[index] = sourceID
                pending -= 1
                guard pending == 0 else { return }

                var didChange = false
                var seenIDs = Set<UUID>()
                for sourceID in recordIDs {
                    guard let sourceID, seenIDs.insert(sourceID).inserted,
                          let source = store.items.first(where: { $0.id == sourceID && !$0.isDeleted }) else { continue }

                    let currentIDs = store.compositionMembers(for: source).map(\.id)
                    if source.compositionID == compositionID,
                       previewSourceID == sourceID,
                       previewOrder.count == currentIDs.count,
                       Set(previewOrder) == Set(currentIDs) {
                        store.setCompositionMemberOrder(previewOrder, in: compositionID)
                        didChange = true
                    } else {
                        didChange = store.addToComposition(sourceID, in: compositionID, before: destinationID) || didChange
                    }
                }
                completion(didChange)
            }
        }
        return true
    }
}

/// Both the container and its members accept records. Only same-group drags preview a reorder.
struct CompositionRecordDropDelegate: DropDelegate {
    let destinationID: UUID?
    let compositionID: UUID?
    let store: CaptureStore
    @Binding var previewOrder: [UUID]
    @Binding var draggingMemberID: UUID?
    @Binding var insertionMemberID: UUID?
    @Binding var isDropTarget: Bool

    func validateDrop(info: DropInfo) -> Bool {
        compositionID != nil && info.hasItemsConforming(to: [.shixuCaptureRecord])
    }

    func dropEntered(info: DropInfo) {
        guard let compositionID else { return }
        isDropTarget = true
        let members = store.compositionGroups.first(where: { $0.id == compositionID })?.members ?? []
        guard let sourceID = CaptureDragProvider.draggedRecordID,
              members.contains(where: { $0.id == sourceID }) else {
            previewOrder = members.map(\.id)
            draggingMemberID = nil
            insertionMemberID = destinationID
            return
        }
        if draggingMemberID != sourceID {
            previewOrder = members.map(\.id)
            draggingMemberID = sourceID
        }
        guard let destinationID,
              let sourceIndex = previewOrder.firstIndex(of: sourceID),
              let destinationIndex = previewOrder.firstIndex(of: destinationID) else { return }
        withAnimation(.snappy(duration: 0.22, extraBounce: 0.08)) {
            if sourceIndex != destinationIndex {
                let movingID = previewOrder.remove(at: sourceIndex)
                previewOrder.insert(movingID, at: destinationIndex)
            }
            insertionMemberID = sourceID
        }
    }

    func dropExited(info: DropInfo) {
        isDropTarget = false
        if draggingMemberID == nil { insertionMemberID = nil }
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        guard let compositionID else { return false }
        let accepted = CompositionDropHandler.receive(
            info.itemProviders(for: [.shixuCaptureRecord]),
            store: store,
            compositionID: compositionID,
            before: destinationID,
            previewOrder: previewOrder,
            previewSourceID: draggingMemberID
        ) { _ in
            withAnimation(.snappy(duration: 0.22, extraBounce: 0.08)) {
                previewOrder = store.compositionGroups.first(where: { $0.id == compositionID })?.members.map(\.id) ?? []
                draggingMemberID = nil
                insertionMemberID = nil
                isDropTarget = false
            }
        }
        if !accepted { isDropTarget = false }
        return accepted
    }
}
