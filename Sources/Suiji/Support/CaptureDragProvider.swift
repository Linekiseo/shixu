import AppKit
import Foundation
import UniformTypeIdentifiers

extension UTType {
    static let shixuCaptureRecord = UTType(exportedAs: "com.suiji.app.capture-record")
}

@MainActor
enum CaptureDragProvider {
    // A hover hint for our own-process drags. The drop still verifies the provider payload.
    private(set) static var draggedRecordID: UUID?

    static func make(store: CaptureStore, item: CaptureItem) -> NSItemProvider {
        draggedRecordID = item.id
        let provider = NSItemProvider()
        provider.suggestedName = item.fileName ?? item.title

        let recordData = Data(item.id.uuidString.utf8)
        provider.registerDataRepresentation(
            forTypeIdentifier: UTType.shixuCaptureRecord.identifier,
            visibility: .ownProcess
        ) { completion in
            completion(recordData, nil)
            return nil
        }

        if let fileURL = store.attachmentURL(for: item) {
            registerFile(fileURL, with: provider)
        } else if item.kind == .web, let url = URL(string: item.body) {
            provider.registerObject(url as NSURL, visibility: .all)
        } else {
            let text = item.body.isEmpty ? item.title : item.body
            provider.registerObject(text as NSString, visibility: .all)
        }
        return provider
    }

    static func loadRecordID(from provider: NSItemProvider, completion: @escaping @MainActor (UUID?) -> Void) {
        provider.loadDataRepresentation(forTypeIdentifier: UTType.shixuCaptureRecord.identifier) { data, _ in
            let id = data
                .flatMap { String(data: $0, encoding: .utf8) }
                .flatMap(UUID.init(uuidString:))
            Task { @MainActor in completion(id) }
        }
    }

    private static func registerFile(_ url: URL, with provider: NSItemProvider) {
        let contentType = (try? url.resourceValues(forKeys: [.contentTypeKey]).contentType) ?? .data
        provider.registerFileRepresentation(
            forTypeIdentifier: contentType.identifier,
            fileOptions: [.openInPlace],
            visibility: .all
        ) { completion in
            completion(url, true, nil)
            return nil
        }
        provider.registerObject(url as NSURL, visibility: .all)
    }
}
