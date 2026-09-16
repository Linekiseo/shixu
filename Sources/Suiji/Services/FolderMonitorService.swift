import Combine
import CoreServices
import Foundation

@MainActor
final class FolderMonitorService: ObservableObject {
    static let shared = FolderMonitorService()

    @Published private(set) var folders: [WatchedFolder]
    @Published private(set) var isRunning = false

    private weak var store: CaptureStore?
    private var stream: FSEventStreamRef?
    private var knownModificationDates: [String: Date] = [:]

    private init() {
        if let data = UserDefaults.standard.data(forKey: "watchedFolders"),
           let decoded = try? JSONDecoder().decode([WatchedFolder].self, from: data) {
            folders = decoded
        } else {
            folders = []
        }
    }

    func start(store: CaptureStore) {
        self.store = store
        rebuildStream()
    }

    func stop() {
        stopStream()
        knownModificationDates.removeAll()
    }

    func addFolder(_ url: URL) {
        guard !folders.contains(where: { $0.path == url.path }) else { return }
        folders.append(WatchedFolder(path: url.path))
        persist()
        rebuildStream()
    }

    func removeFolder(_ id: WatchedFolder.ID) {
        folders.removeAll(where: { $0.id == id })
        persist()
        rebuildStream()
    }

    func setEnabled(_ enabled: Bool, for id: WatchedFolder.ID) {
        guard let index = folders.firstIndex(where: { $0.id == id }) else { return }
        folders[index].isEnabled = enabled
        persist()
        rebuildStream()
    }

    fileprivate func handle(paths: [String]) {
        for path in paths {
            let url = URL(fileURLWithPath: path)
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory) else { continue }
            if isDirectory.boolValue {
                scanDirectory(url, emitChanges: true)
            } else {
                inspectFile(url, emitChanges: true)
            }
        }
    }

    private func rebuildStream() {
        stopStream()
        knownModificationDates.removeAll()

        let enabledFolders = folders.filter(\.isEnabled)
        for folder in enabledFolders { scanDirectory(folder.url, emitChanges: false) }
        guard !enabledFolders.isEmpty else {
            isRunning = false
            return
        }

        var context = FSEventStreamContext(
            version: 0,
            info: Unmanaged.passUnretained(self).toOpaque(),
            retain: nil,
            release: nil,
            copyDescription: nil
        )
        let paths = enabledFolders.map(\.path) as CFArray
        let flags = UInt32(kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagUseCFTypes | kFSEventStreamCreateFlagNoDefer)

        stream = FSEventStreamCreate(
            kCFAllocatorDefault,
            folderMonitorCallback,
            &context,
            paths,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            0.6,
            flags
        )
        guard let stream else { return }
        FSEventStreamSetDispatchQueue(stream, DispatchQueue.global(qos: .utility))
        isRunning = FSEventStreamStart(stream)
    }

    private func stopStream() {
        guard let stream else { return }
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
        self.stream = nil
        isRunning = false
    }

    private func scanDirectory(_ directory: URL, emitChanges: Bool) {
        guard let enumerator = FileManager.default.enumerator(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey, .isHiddenKey, .contentModificationDateKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else { return }

        while let url = enumerator.nextObject() as? URL {
            inspectFile(url, emitChanges: emitChanges)
        }
    }

    private func inspectFile(_ url: URL, emitChanges: Bool) {
        guard let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .isHiddenKey, .contentModificationDateKey]),
              values.isRegularFile == true, values.isHidden != true else { return }
        let modificationDate = values.contentModificationDate ?? .distantPast
        let previous = knownModificationDates[url.path]
        knownModificationDates[url.path] = modificationDate
        guard emitChanges, previous == nil || modificationDate > previous! else { return }
        store?.receiveDetectedFile(url)
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(folders) {
            UserDefaults.standard.set(data, forKey: "watchedFolders")
        }
    }
}

private let folderMonitorCallback: FSEventStreamCallback = { _, info, count, eventPaths, _, _ in
    guard let info else { return }
    let service = Unmanaged<FolderMonitorService>.fromOpaque(info).takeUnretainedValue()
    let paths = unsafeBitCast(eventPaths, to: NSArray.self) as? [String] ?? []
    let bounded = Array(paths.prefix(count))
    Task { @MainActor in
        service.handle(paths: bounded)
    }
}
