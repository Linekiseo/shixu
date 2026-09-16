import Foundation

enum PersistenceService {
    static var applicationDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let directory = base.appendingPathComponent("Suiji", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    static var attachmentsDirectory: URL {
        let directory = applicationDirectory.appendingPathComponent("Attachments", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private static var itemsURL: URL {
        applicationDirectory.appendingPathComponent("captures.json")
    }

    static func loadItems() -> [CaptureItem]? {
        guard let data = try? Data(contentsOf: itemsURL) else { return nil }
        return try? JSONDecoder.suiji.decode([CaptureItem].self, from: data)
    }

    static func saveItems(_ items: [CaptureItem]) {
        guard let data = try? JSONEncoder.suiji.encode(items) else { return }
        try? data.write(to: itemsURL, options: [.atomic])
    }

    static func saveImageData(_ data: Data, itemID: UUID) -> String? {
        let relativePath = "\(itemID.uuidString)-clipboard.png"
        let destination = attachmentsDirectory.appendingPathComponent(relativePath)
        do {
            try data.write(to: destination, options: [.atomic])
            return relativePath
        } catch {
            return nil
        }
    }

    static func saveTextContent(
        _ text: String,
        itemID: UUID,
        fileName: String,
        destinationDirectory: URL? = nil
    ) -> String? {
        let relativePath = "Text/\(itemID.uuidString)/\(fileName)"
        let destination = (destinationDirectory ?? attachmentsDirectory).appendingPathComponent(relativePath)
        do {
            try FileManager.default.createDirectory(
                at: destination.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try Data(text.utf8).write(to: destination, options: [.atomic])
            return relativePath
        } catch {
            return nil
        }
    }

    static func resolveAttachment(_ path: String) -> URL? {
        let url = attachmentsDirectory.appendingPathComponent(path)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    static func deleteAttachment(_ path: String) {
        let url = attachmentsDirectory.appendingPathComponent(path)
        try? FileManager.default.removeItem(at: url)
        let parent = url.deletingLastPathComponent()
        if parent != attachmentsDirectory,
           (try? FileManager.default.contentsOfDirectory(atPath: parent.path).isEmpty) == true {
            try? FileManager.default.removeItem(at: parent)
        }
    }
}

private extension JSONEncoder {
    static let suiji: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()
}

private extension JSONDecoder {
    static let suiji: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}
