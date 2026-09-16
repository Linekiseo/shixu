import Foundation

struct StoredWebArchive: Sendable {
    let relativePath: String
    let originalSize: Int64
    let compressedSize: Int64
}

enum WebArchiveStorageService {
    private static var archiveDirectory: URL {
        let directory = PersistenceService.applicationDirectory.appendingPathComponent("WebArchives", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private static var restoreDirectory: URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("SuijiWebArchives", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    static func store(
        _ archiveData: Data,
        itemID: UUID,
        destinationDirectory: URL? = nil
    ) -> StoredWebArchive? {
        guard let compressed = try? (archiveData as NSData).compressed(using: .lzfse) as Data else { return nil }
        let relativePath = "\(itemID.uuidString).webarchive.lzfse"
        let directory = destinationDirectory ?? archiveDirectory
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        do {
            try compressed.write(to: directory.appendingPathComponent(relativePath), options: .atomic)
            return StoredWebArchive(
                relativePath: relativePath,
                originalSize: Int64(archiveData.count),
                compressedSize: Int64(compressed.count)
            )
        } catch {
            return nil
        }
    }

    static func restoredURL(
        relativePath: String,
        sourceDirectory: URL? = nil,
        destinationDirectory: URL? = nil
    ) -> URL? {
        let source = (sourceDirectory ?? archiveDirectory).appendingPathComponent(relativePath)
        let restoredRoot = destinationDirectory ?? restoreDirectory
        try? FileManager.default.createDirectory(at: restoredRoot, withIntermediateDirectories: true)
        let archiveName = URL(fileURLWithPath: relativePath).deletingPathExtension().lastPathComponent
        let destination = restoredRoot.appendingPathComponent(archiveName)

        if FileManager.default.fileExists(atPath: destination.path),
           let sourceDate = try? source.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate,
           let destinationDate = try? destination.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate,
           destinationDate >= sourceDate {
            return destination
        }

        guard let compressed = try? NSData(contentsOf: source, options: .mappedIfSafe),
              let archiveData = try? compressed.decompressed(using: .lzfse) as Data else { return nil }
        do {
            try archiveData.write(to: destination, options: .atomic)
            return destination
        } catch {
            return nil
        }
    }

    static func delete(relativePath: String) {
        try? FileManager.default.removeItem(at: archiveDirectory.appendingPathComponent(relativePath))
        let archiveName = URL(fileURLWithPath: relativePath).deletingPathExtension().lastPathComponent
        try? FileManager.default.removeItem(at: restoreDirectory.appendingPathComponent(archiveName))
    }
}
