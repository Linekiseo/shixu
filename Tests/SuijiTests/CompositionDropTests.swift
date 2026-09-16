import AppKit
import UniformTypeIdentifiers
import XCTest
@testable import Suiji

final class CompositionDropTests: XCTestCase {
    @MainActor
    func testPayloadLoadingStartsBeforeDropReturns() async throws {
        let items = makeItems(count: 3)
        let store = CaptureStore(testItems: items)
        XCTAssertTrue(store.combine(items[0].id, onto: items[1].id))
        let groupID = try XCTUnwrap(store.compositionGroups.first?.id)
        let provider = ImmediateLoadProbe()
        let data = Data(items[2].id.uuidString.utf8)
        provider.registerDataRepresentation(forTypeIdentifier: UTType.shixuCaptureRecord.identifier, visibility: .ownProcess) {
            $0(data, nil)
            return nil
        }

        let result: Bool = await withCheckedContinuation { continuation in
            let accepted = CompositionDropHandler.receive([provider], store: store, compositionID: groupID) {
                continuation.resume(returning: $0)
            }
            XCTAssertTrue(accepted)
            XCTAssertTrue(provider.didStartLoading, "macOS requires loading to start within the drop callback")
            if !accepted { continuation.resume(returning: false) }
        }
        XCTAssertTrue(result)
        XCTAssertEqual(store.compositionGroups.first?.members.count, 3)
    }

    @MainActor
    func testExistingPairAcceptsRepeatedRecordDropsAndSurvivesReload() async throws {
        let items = makeItems(count: 8)
        let store = CaptureStore(testItems: items)
        XCTAssertTrue(store.combine(items[0].id, onto: items[1].id))
        let groupID = try XCTUnwrap(store.compositionGroups.first?.id)

        for index in 2..<items.count {
            let result = await drop(items[index], into: groupID, store: store)
            XCTAssertTrue(result)
            XCTAssertEqual(store.compositionGroups.first?.members.count, index + 1)
            XCTAssertEqual(store.compositionGroups.first?.members.last?.id, items[index].id)
        }

        XCTAssertEqual(store.compositionGroups.count, 1)
        XCTAssertEqual(store.compositionGroups.first?.members.map(\.id), items.map(\.id))
        XCTAssertEqual(store.items.count, items.count)
        let reloadedItems = try JSONDecoder().decode([CaptureItem].self, from: JSONEncoder().encode(store.items))
        let reloaded = CaptureStore(testItems: reloadedItems)
        XCTAssertEqual(reloaded.compositionGroups.first?.members.map(\.id), items.map(\.id))
    }

    @MainActor
    func testDropOntoMemberInsertsNewCardInsteadOfOnlyCommittingOldOrder() async throws {
        let items = makeItems(count: 3)
        let store = CaptureStore(testItems: items)
        XCTAssertTrue(store.combine(items[0].id, onto: items[1].id))
        let groupID = try XCTUnwrap(store.compositionGroups.first?.id)

        let result = await drop(items[2], into: groupID, before: items[1].id, store: store,
                                previewOrder: [items[0].id, items[1].id])

        XCTAssertTrue(result)
        XCTAssertEqual(store.compositionGroups.first?.members.map(\.id), [items[0].id, items[2].id, items[1].id])
    }

    @MainActor
    func testMergingTwoGroupsKeepsBothSavedOrdersWithoutInterleaving() async throws {
        let items = makeItems(count: 4)
        let store = CaptureStore(testItems: items)
        XCTAssertTrue(store.combine(items[0].id, onto: items[1].id))
        XCTAssertTrue(store.combine(items[2].id, onto: items[3].id))
        let targetID = try XCTUnwrap(store.items.first(where: { $0.id == items[0].id })?.compositionID)
        let sourceID = try XCTUnwrap(store.items.first(where: { $0.id == items[2].id })?.compositionID)
        store.setCompositionMemberOrder([items[1].id, items[0].id], in: targetID)
        store.setCompositionMemberOrder([items[3].id, items[2].id], in: sourceID)

        let result = await drop(items[2], into: targetID, store: store)

        XCTAssertTrue(result)
        XCTAssertEqual(store.compositionGroups.count, 1)
        XCTAssertEqual(store.compositionGroups.first?.id, targetID)
        XCTAssertEqual(store.compositionGroups.first?.members.map(\.id), [items[1].id, items[0].id, items[3].id, items[2].id])
        XCTAssertEqual(store.compositionGroups.first?.members.map(\.compositionOrder), [0, 1, 2, 3])
    }

    @MainActor
    func testOrdinaryCardCombineCanExtendAGroupWithoutLosingItsOrder() throws {
        let items = makeItems(count: 4)
        let store = CaptureStore(testItems: items)
        XCTAssertTrue(store.combine(items[0].id, onto: items[1].id))
        let groupID = try XCTUnwrap(store.compositionGroups.first?.id)
        store.setCompositionMemberOrder([items[1].id, items[0].id], in: groupID)

        XCTAssertTrue(store.combine(items[2].id, onto: items[0].id))
        XCTAssertTrue(store.combine(items[0].id, onto: items[3].id))
        XCTAssertEqual(store.compositionGroups.first?.members.map(\.id), [items[1].id, items[0].id, items[2].id, items[3].id])
    }

    @MainActor
    func testReorderingStillCommitsAnimatedPreviewAfterAddingThirdCard() async throws {
        let items = makeItems(count: 3)
        let store = CaptureStore(testItems: items)
        XCTAssertTrue(store.combine(items[0].id, onto: items[1].id))
        let groupID = try XCTUnwrap(store.compositionGroups.first?.id)
        XCTAssertTrue(store.addToComposition(items[2].id, in: groupID))
        let order = [items[2].id, items[0].id, items[1].id]

        let result = await drop(items[2], into: groupID, before: items[0].id, store: store,
                                previewOrder: order, previewSourceID: items[2].id)

        XCTAssertTrue(result)
        XCTAssertEqual(store.compositionGroups.first?.members.map(\.id), order)
        XCTAssertEqual(store.items.count, 3)
    }

    @MainActor
    func testStaleReorderStateDoesNotSwallowAnIncomingRecord() async throws {
        let items = makeItems(count: 3)
        let store = CaptureStore(testItems: items)
        XCTAssertTrue(store.combine(items[0].id, onto: items[1].id))
        let groupID = try XCTUnwrap(store.compositionGroups.first?.id)

        let result = await drop(items[2], into: groupID, store: store,
                                previewOrder: [items[1].id, items[0].id], previewSourceID: items[0].id)

        XCTAssertTrue(result)
        XCTAssertEqual(store.compositionGroups.first?.members.map(\.id), items.map(\.id))
    }

    @MainActor
    func testDuplicatePayloadsAndSameGroupDropsNeverDuplicateMembers() async throws {
        let items = makeItems(count: 3)
        let store = CaptureStore(testItems: items)
        XCTAssertTrue(store.combine(items[0].id, onto: items[1].id))
        let groupID = try XCTUnwrap(store.compositionGroups.first?.id)
        let provider = CaptureDragProvider.make(store: store, item: items[2])
        let result = await receive([provider, provider], into: groupID, store: store)
        XCTAssertTrue(result)

        let repeated = await drop(items[2], into: groupID, store: store)
        XCTAssertTrue(repeated)
        XCTAssertEqual(store.compositionGroups.first?.members.map(\.id), items.map(\.id))
        XCTAssertEqual(store.items.count, 3)
    }

    @MainActor
    func testInvalidAndDeletedRecordPayloadsLeaveTheGroupUntouched() async throws {
        let items = makeItems(count: 3)
        let store = CaptureStore(testItems: items)
        XCTAssertTrue(store.combine(items[0].id, onto: items[1].id))
        let groupID = try XCTUnwrap(store.compositionGroups.first?.id)
        let provider = NSItemProvider()
        provider.registerDataRepresentation(forTypeIdentifier: UTType.shixuCaptureRecord.identifier, visibility: .ownProcess) {
            $0(Data("invalid-record-id".utf8), nil)
            return nil
        }
        let invalid = await receive([provider], into: groupID, store: store)
        XCTAssertFalse(invalid)

        store.moveToTrash(items[2].id)
        let deleted = await drop(items[2], into: groupID, store: store)
        XCTAssertFalse(deleted)
        XCTAssertEqual(store.compositionGroups.first?.members.map(\.id), [items[0].id, items[1].id])
        XCTAssertFalse(CompositionDropHandler.receive([NSItemProvider(object: "unrelated text" as NSString)], store: store, compositionID: groupID))
    }

    @MainActor
    func testMissingDestinationDoesNotCreateOrResurrectAGroup() async throws {
        let items = makeItems(count: 3)
        let store = CaptureStore(testItems: items)
        XCTAssertTrue(store.combine(items[0].id, onto: items[1].id))
        let groupID = try XCTUnwrap(store.compositionGroups.first?.id)
        store.dissolveComposition(groupID)

        let result = await drop(items[2], into: groupID, store: store)

        XCTAssertFalse(result)
        XCTAssertTrue(store.compositionGroups.isEmpty)
        XCTAssertTrue(store.items.allSatisfy { $0.compositionID == nil })
    }

    private func makeItems(count: Int) -> [CaptureItem] {
        let kinds: [CaptureKind] = [.text, .image, .file, .web]
        return (0..<count).map { index in
            CaptureItem(createdAt: Date(timeIntervalSince1970: Double(index)), kind: kinds[index % kinds.count],
                        title: "卡片 \(index)", body: "内容 \(index)", source: "拖拽回归测试")
        }
    }

    @MainActor
    private func drop(_ item: CaptureItem, into compositionID: UUID, before destinationID: UUID? = nil,
                      store: CaptureStore, previewOrder: [UUID] = [], previewSourceID: UUID? = nil) async -> Bool {
        await receive([CaptureDragProvider.make(store: store, item: item)], into: compositionID,
                      before: destinationID, store: store, previewOrder: previewOrder, previewSourceID: previewSourceID)
    }

    @MainActor
    private func receive(_ providers: [NSItemProvider], into compositionID: UUID, before destinationID: UUID? = nil,
                         store: CaptureStore, previewOrder: [UUID] = [], previewSourceID: UUID? = nil) async -> Bool {
        await withCheckedContinuation { continuation in
            let accepted = CompositionDropHandler.receive(providers, store: store, compositionID: compositionID,
                                                          before: destinationID, previewOrder: previewOrder,
                                                          previewSourceID: previewSourceID) { result in
                continuation.resume(returning: result)
            }
            if !accepted { continuation.resume(returning: false) }
        }
    }
}

private final class ImmediateLoadProbe: NSItemProvider, @unchecked Sendable {
    private let lock = NSLock()
    private var started = false

    var didStartLoading: Bool { lock.withLock { started } }

    override func loadDataRepresentation(
        forTypeIdentifier typeIdentifier: String,
        completionHandler: @escaping @Sendable (Data?, (any Error)?) -> Void
    ) -> Progress {
        lock.withLock { started = true }
        return super.loadDataRepresentation(forTypeIdentifier: typeIdentifier, completionHandler: completionHandler)
    }
}
