import AppKit
import Foundation
@preconcurrency import WebKit

struct WebArchivePreviewSource: Hashable, Sendable {
    let itemID: UUID
    let relativePath: String
    let capturedAt: Date?

    var cacheKey: String {
        let version = Int((capturedAt?.timeIntervalSince1970 ?? 0) * 1_000)
        return "\(itemID.uuidString)-\(version)"
    }
}

extension CaptureItem {
    var webArchivePreviewSource: WebArchivePreviewSource? {
        guard webArchiveState == .archived, let webArchivePath else { return nil }
        return WebArchivePreviewSource(
            itemID: id,
            relativePath: webArchivePath,
            capturedAt: webArchiveCapturedAt
        )
    }
}

@MainActor
final class WebArchiveThumbnailService: NSObject, WKNavigationDelegate {
    static let shared = WebArchiveThumbnailService()

    private struct Job {
        let source: WebArchivePreviewSource
        let archiveURL: URL
    }

    private let memoryCache = NSCache<NSString, NSImage>()
    private var waiters: [String: [CheckedContinuation<NSImage?, Never>]] = [:]
    private var queue: [Job] = []
    private var activeJob: Job?
    private var webView: WKWebView?
    private var timeoutTask: Task<Void, Never>?
    private var isTakingSnapshot = false

    override private init() {
        super.init()
        memoryCache.countLimit = 100
        memoryCache.totalCostLimit = 80 * 1_024 * 1_024
    }

    func image(for source: WebArchivePreviewSource) async -> NSImage? {
        let key = source.cacheKey
        if let image = memoryCache.object(forKey: key as NSString) { return image }

        if let data = await WebArchiveThumbnailDiskCache.shared.lookup(key: key),
           let image = NSImage(data: data) {
            cache(image, key: key)
            return image
        }

        let archiveURL = await Task.detached(priority: .utility) {
            WebArchiveStorageService.restoredURL(relativePath: source.relativePath)
        }.value
        guard let archiveURL else { return nil }

        return await withCheckedContinuation { continuation in
            let shouldEnqueue = waiters[key] == nil
            waiters[key, default: []].append(continuation)
            if shouldEnqueue {
                queue.append(Job(source: source, archiveURL: archiveURL))
                startNextIfNeeded()
            }
        }
    }

    func clearCache() {
        memoryCache.removeAllObjects()
        Task { await WebArchiveThumbnailDiskCache.shared.removeAll() }
    }

    private func startNextIfNeeded() {
        guard activeJob == nil, !queue.isEmpty else { return }
        let job = queue.removeFirst()
        activeJob = job
        isTakingSnapshot = false

        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = false
        let view = WKWebView(
            frame: CGRect(x: 0, y: 0, width: 1_200, height: 720),
            configuration: configuration
        )
        view.navigationDelegate = self
        view.underPageBackgroundColor = .windowBackgroundColor
        webView = view
        view.loadFileURL(job.archiveURL, allowingReadAccessTo: job.archiveURL.deletingLastPathComponent())

        timeoutTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(15))
            guard !Task.isCancelled, let self, self.activeJob?.source.cacheKey == job.source.cacheKey else { return }
            self.finish(image: nil)
        }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        guard activeJob != nil, !isTakingSnapshot else { return }
        isTakingSnapshot = true
        webView.evaluateJavaScript(WebArchiveOfflinePresentation.normalizationScript) { [weak self, weak webView] _, _ in
            guard let self, let webView else { return }
            Task { @MainActor [weak self, weak webView] in
                try? await Task.sleep(for: .milliseconds(320))
                guard let self, let webView, self.activeJob != nil else { return }
                let configuration = WKSnapshotConfiguration()
                configuration.rect = webView.bounds
                configuration.snapshotWidth = 900
                webView.takeSnapshot(with: configuration) { [weak self] image, _ in
                    self?.finish(image: image)
                }
            }
        }
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        finish(image: nil)
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        finish(image: nil)
    }

    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction,
        decisionHandler: @escaping @MainActor (WKNavigationActionPolicy) -> Void
    ) {
        guard let scheme = navigationAction.request.url?.scheme?.lowercased() else {
            decisionHandler(.cancel)
            return
        }
        decisionHandler(scheme == "file" || scheme == "about" || scheme == "data" ? .allow : .cancel)
    }

    private func finish(image: NSImage?) {
        guard let job = activeJob else { return }
        let key = job.source.cacheKey
        timeoutTask?.cancel()
        timeoutTask = nil
        webView?.stopLoading()
        webView?.navigationDelegate = nil
        webView = nil
        activeJob = nil
        isTakingSnapshot = false

        if let image {
            cache(image, key: key)
            if let sourceData = image.tiffRepresentation,
               let jpegData = WebPreviewImageCodec.thumbnailJPEGData(from: sourceData) {
                Task {
                    await WebArchiveThumbnailDiskCache.shared.store(
                        imageData: jpegData,
                        key: key,
                        itemID: job.source.itemID
                    )
                }
            }
        }

        let continuations = waiters.removeValue(forKey: key) ?? []
        continuations.forEach { $0.resume(returning: image) }
        startNextIfNeeded()
    }

    private func cache(_ image: NSImage, key: String) {
        let width = max(Int(image.size.width), 1)
        let height = max(Int(image.size.height), 1)
        memoryCache.setObject(image, forKey: key as NSString, cost: width * height * 4)
    }
}

private actor WebArchiveThumbnailDiskCache {
    static let shared = WebArchiveThumbnailDiskCache()
    private let directory: URL

    private init() {
        let root = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        directory = root.appendingPathComponent("Suiji/WebArchivePreviews", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    func lookup(key: String) -> Data? {
        try? Data(contentsOf: destination(for: key), options: .mappedIfSafe)
    }

    func store(imageData: Data, key: String, itemID: UUID) {
        try? imageData.write(to: destination(for: key), options: .atomic)
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil
        ) else { return }
        let prefix = itemID.uuidString + "-"
        for file in files where file.lastPathComponent.hasPrefix(prefix) && file.deletingPathExtension().lastPathComponent != key {
            try? FileManager.default.removeItem(at: file)
        }
    }

    func removeAll() {
        try? FileManager.default.removeItem(at: directory)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    private func destination(for key: String) -> URL {
        directory.appendingPathComponent(key).appendingPathExtension("jpg")
    }
}
