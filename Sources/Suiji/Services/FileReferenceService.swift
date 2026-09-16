import Foundation

struct FileReferenceResult {
    var bookmark: Data?
    var originalPath: String
    var fileSize: Int64?
    var fileExtension: String
    var backupPath: String?
    var backupOriginalSize: Int64?
    var backupCompressedSize: Int64?
}

enum FileReferenceService {
    static func register(url: URL, itemID: UUID, mode: FileStorageMode) -> FileReferenceResult {
        let didAccess = url.startAccessingSecurityScopedResource()
        defer { if didAccess { url.stopAccessingSecurityScopedResource() } }

        let values = try? url.resourceValues(forKeys: [.fileSizeKey, .totalFileAllocatedSizeKey])
        let size = values?.fileSize.map(Int64.init) ?? values?.totalFileAllocatedSize.map(Int64.init)
        let bookmark = try? url.bookmarkData(
            options: [.withSecurityScope],
            includingResourceValuesForKeys: [.fileSizeKey, .contentModificationDateKey],
            relativeTo: nil
        )

        var result = FileReferenceResult(
            bookmark: bookmark,
            originalPath: url.path,
            fileSize: size,
            fileExtension: url.pathExtension.uppercased(),
            backupPath: nil,
            backupOriginalSize: nil,
            backupCompressedSize: nil
        )

        if mode == .compressedBackup,
           let backup = LZFSEBackupService.createBackup(from: url, itemID: itemID) {
            result.backupPath = backup.relativePath
            result.backupOriginalSize = backup.originalSize
            result.backupCompressedSize = backup.compressedSize
        }
        return result
    }

    static func resolve(bookmark: Data?, fallbackPath: String?) -> URL? {
        if let bookmark {
            var isStale = false
            if let url = try? URL(
                resolvingBookmarkData: bookmark,
                options: [.withSecurityScope],
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            ), FileManager.default.fileExists(atPath: url.path) {
                return url
            }
        }
        if let fallbackPath, FileManager.default.fileExists(atPath: fallbackPath) {
            return URL(fileURLWithPath: fallbackPath)
        }
        return nil
    }
}

struct LZFSEBackupResult {
    var relativePath: String
    var originalSize: Int64
    var compressedSize: Int64
}

enum LZFSEBackupService {
    private static var backupDirectory: URL {
        let directory = PersistenceService.applicationDirectory.appendingPathComponent("CompressedBackups", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private static var restoreCacheDirectory: URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("SuijiRestored", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    static func createBackup(
        from url: URL,
        itemID: UUID,
        destinationDirectory: URL? = nil
    ) -> LZFSEBackupResult? {
        guard let source = try? NSData(contentsOf: url, options: [.mappedIfSafe]),
              let compressed = try? source.compressed(using: .lzfse) as Data else { return nil }
        let relativePath = "\(itemID.uuidString)-\(url.lastPathComponent).lzfse"
        let directory = destinationDirectory ?? backupDirectory
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let destination = directory.appendingPathComponent(relativePath)
        do {
            try compressed.write(to: destination, options: [.atomic])
            return LZFSEBackupResult(
                relativePath: relativePath,
                originalSize: Int64(source.length),
                compressedSize: Int64(compressed.count)
            )
        } catch {
            return nil
        }
    }

    static func restoredURL(
        relativePath: String,
        originalName: String,
        sourceDirectory: URL? = nil,
        restoreDirectory: URL? = nil
    ) -> URL? {
        let backupURL = (sourceDirectory ?? backupDirectory).appendingPathComponent(relativePath)
        let cacheRoot = restoreDirectory ?? restoreCacheDirectory
        let itemCache = cacheRoot.appendingPathComponent(relativePath, isDirectory: true)
        try? FileManager.default.createDirectory(at: itemCache, withIntermediateDirectories: true)
        let destination = itemCache.appendingPathComponent(originalName)

        if FileManager.default.fileExists(atPath: destination.path),
           let backupDate = try? backupURL.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate,
           let restoredDate = try? destination.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate,
           restoredDate >= backupDate {
            return destination
        }

        guard let compressed = try? NSData(contentsOf: backupURL, options: [.mappedIfSafe]),
              let decompressed = try? compressed.decompressed(using: .lzfse) as Data else { return nil }
        do {
            try decompressed.write(to: destination, options: [.atomic])
            return destination
        } catch {
            return nil
        }
    }


    static func deleteBackup(relativePath: String) {
        try? FileManager.default.removeItem(at: backupDirectory.appendingPathComponent(relativePath))
        try? FileManager.default.removeItem(at: restoreCacheDirectory.appendingPathComponent(relativePath))
    }
}
