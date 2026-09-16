import AppKit
import CryptoKit
import Foundation
import ImageIO
@preconcurrency import LinkPresentation
import UniformTypeIdentifiers

enum WebPreviewCachePolicy {
    static let maximumConcurrentLoads = 3
    static let positiveLifetime: TimeInterval = 14 * 24 * 60 * 60
    static let negativeLifetime: TimeInterval = 6 * 60 * 60

    static func canonicalURLString(for url: URL) -> String {
        guard var components = URLComponents(url: url.absoluteURL, resolvingAgainstBaseURL: true) else {
            return url.absoluteString
        }
        components.scheme = components.scheme?.lowercased()
        components.host = components.host?.lowercased()
        components.fragment = nil
        if (components.scheme == "https" && components.port == 443)
            || (components.scheme == "http" && components.port == 80) {
            components.port = nil
        }
        return components.string ?? url.absoluteString
    }

    static func cacheKey(for url: URL) -> String {
        let digest = SHA256.hash(data: Data(canonicalURLString(for: url).utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}

@MainActor
final class WebPreviewService {
    static let shared = WebPreviewService()

    struct Subscription: Hashable {
        fileprivate let id: UUID
        fileprivate let key: String
    }

    private enum RequestState {
        case checkingDisk
        case queued
        case loading
    }

    private final class Request {
        let key: String
        let url: URL
        var subscribers: [UUID: (NSImage?) -> Void]
        var state: RequestState = .checkingDisk
        var provider: LPMetadataProvider?
        var task: Task<Void, Never>?

        init(key: String, url: URL, subscriberID: UUID, completion: @escaping (NSImage?) -> Void) {
            self.key = key
            self.url = url
            subscribers = [subscriberID: completion]
        }
    }

    private let memoryCache = NSCache<NSString, NSImage>()
    private var requests: [String: Request] = [:]
    private var waitingKeys: [String] = []
    private var runningCount = 0

    private init() {
        memoryCache.countLimit = 160
        memoryCache.totalCostLimit = 96 * 1_024 * 1_024
    }

    @discardableResult
    func subscribe(to url: URL, completion: @escaping (NSImage?) -> Void) -> Subscription {
        let key = WebPreviewCachePolicy.cacheKey(for: url)
        let id = UUID()
        let subscription = Subscription(id: id, key: key)

        if let image = memoryCache.object(forKey: key as NSString) {
            Task { @MainActor in
                await Task.yield()
                completion(image)
            }
            return subscription
        }

        if let request = requests[key] {
            request.subscribers[id] = completion
            return subscription
        }

        let request = Request(key: key, url: url, subscriberID: id, completion: completion)
        requests[key] = request
        request.task = Task { [weak self, weak request] in
            guard let self, let request else { return }
            let cached = await WebPreviewDiskCache.shared.lookup(key: key)
            guard !Task.isCancelled else { return }
            self.handleDiskLookup(cached, request: request)
        }
        return subscription
    }

    func unsubscribe(_ subscription: Subscription) {
        guard let request = requests[subscription.key] else { return }
        request.subscribers.removeValue(forKey: subscription.id)
        guard request.subscribers.isEmpty else { return }
        cancel(request)
    }

    func clearCache() {
        memoryCache.removeAllObjects()
        Task { await WebPreviewDiskCache.shared.removeAll() }
    }

    private func handleDiskLookup(_ cached: WebPreviewDiskCache.Lookup, request: Request) {
        guard requests[request.key] === request, !request.subscribers.isEmpty else { return }
        request.task = nil

        switch cached {
        case let .image(data):
            guard let image = NSImage(data: data) else {
                enqueue(request)
                return
            }
            cache(image, forKey: request.key)
            finish(request, image: image)
        case .negative:
            finish(request, image: nil)
        case .miss:
            enqueue(request)
        }
    }

    private func enqueue(_ request: Request) {
        request.state = .queued
        if !waitingKeys.contains(request.key) { waitingKeys.append(request.key) }
        startWaitingRequests()
    }

    private func startWaitingRequests() {
        while runningCount < WebPreviewCachePolicy.maximumConcurrentLoads, !waitingKeys.isEmpty {
            let key = waitingKeys.removeFirst()
            guard let request = requests[key], !request.subscribers.isEmpty else { continue }
            start(request)
        }
    }

    private func start(_ request: Request) {
        request.state = .loading
        runningCount += 1
        let provider = LPMetadataProvider()
        provider.timeout = 6
        request.provider = provider
        request.task = Task { [weak self, weak request] in
            guard let self, let request else { return }
            do {
                let metadata = try await provider.startFetchingMetadata(for: request.url)
                guard !Task.isCancelled, self.requests[request.key] === request else { return }
                let itemProvider = metadata.imageProvider ?? metadata.iconProvider
                let sourceData = itemProvider.flatMap { provider in
                    provider.registeredTypeIdentifiers.first(where: {
                        UTType($0)?.conforms(to: .image) == true
                    }).map { (provider, $0) }
                }
                guard let sourceData else {
                    await WebPreviewDiskCache.shared.storeNegative(key: request.key)
                    guard !Task.isCancelled else { return }
                    self.finishLoading(request, image: nil)
                    return
                }

                guard let rawData = await Self.loadData(from: sourceData.0, typeIdentifier: sourceData.1),
                      !Task.isCancelled else {
                    self.finishLoading(request, image: nil)
                    return
                }
                let thumbnailData = await Task.detached(priority: .utility) {
                    WebPreviewImageCodec.thumbnailJPEGData(from: rawData)
                }.value
                guard !Task.isCancelled, self.requests[request.key] === request else { return }
                guard let thumbnailData, let image = NSImage(data: thumbnailData) else {
                    await WebPreviewDiskCache.shared.storeNegative(key: request.key)
                    guard !Task.isCancelled else { return }
                    self.finishLoading(request, image: nil)
                    return
                }
                await WebPreviewDiskCache.shared.store(imageData: thumbnailData, key: request.key)
                guard !Task.isCancelled else { return }
                self.cache(image, forKey: request.key)
                self.finishLoading(request, image: image)
            } catch {
                guard !Task.isCancelled, self.requests[request.key] === request else { return }
                self.finishLoading(request, image: nil)
            }
        }
    }

    private static func loadData(from provider: NSItemProvider, typeIdentifier: String) async -> Data? {
        await withCheckedContinuation { continuation in
            provider.loadDataRepresentation(forTypeIdentifier: typeIdentifier) { data, _ in
                continuation.resume(returning: data)
            }
        }
    }

    private func finishLoading(_ request: Request, image: NSImage?) {
        guard requests[request.key] === request else { return }
        runningCount = max(0, runningCount - 1)
        finish(request, image: image)
        startWaitingRequests()
    }

    private func finish(_ request: Request, image: NSImage?) {
        guard requests[request.key] === request else { return }
        requests.removeValue(forKey: request.key)
        request.provider = nil
        request.task = nil
        let completions = Array(request.subscribers.values)
        request.subscribers.removeAll()
        completions.forEach { $0(image) }
    }

    private func cancel(_ request: Request) {
        guard requests[request.key] === request else { return }
        requests.removeValue(forKey: request.key)
        waitingKeys.removeAll { $0 == request.key }
        request.provider?.cancel()
        request.task?.cancel()
        if case .loading = request.state {
            runningCount = max(0, runningCount - 1)
            startWaitingRequests()
        }
    }

    private func cache(_ image: NSImage, forKey key: String) {
        let width = max(Int(image.size.width), 1)
        let height = max(Int(image.size.height), 1)
        memoryCache.setObject(image, forKey: key as NSString, cost: width * height * 4)
    }
}

private actor WebPreviewDiskCache {
    enum Lookup: Sendable {
        case image(Data)
        case negative
        case miss
    }

    static let shared = WebPreviewDiskCache()
    private let directory: URL

    private init() {
        let root = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        directory = root.appendingPathComponent("Suiji/WebPreviews", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    func lookup(key: String, now: Date = .now) -> Lookup {
        let imageURL = directory.appendingPathComponent(key).appendingPathExtension("jpg")
        if isFresh(imageURL, lifetime: WebPreviewCachePolicy.positiveLifetime, now: now),
           let data = try? Data(contentsOf: imageURL, options: .mappedIfSafe) {
            return .image(data)
        }

        let negativeURL = directory.appendingPathComponent(key).appendingPathExtension("miss")
        if isFresh(negativeURL, lifetime: WebPreviewCachePolicy.negativeLifetime, now: now) {
            return .negative
        }
        return .miss
    }

    func store(imageData: Data, key: String) {
        let destination = directory.appendingPathComponent(key).appendingPathExtension("jpg")
        try? imageData.write(to: destination, options: .atomic)
        try? FileManager.default.removeItem(
            at: directory.appendingPathComponent(key).appendingPathExtension("miss")
        )
    }

    func storeNegative(key: String) {
        let destination = directory.appendingPathComponent(key).appendingPathExtension("miss")
        try? Data().write(to: destination, options: .atomic)
    }

    func removeAll() {
        try? FileManager.default.removeItem(at: directory)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    private func isFresh(_ url: URL, lifetime: TimeInterval, now: Date) -> Bool {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
              let modifiedAt = attributes[.modificationDate] as? Date else { return false }
        if now.timeIntervalSince(modifiedAt) <= lifetime { return true }
        try? FileManager.default.removeItem(at: url)
        return false
    }
}

enum WebPreviewImageCodec {
    static func thumbnailJPEGData(from sourceData: Data) -> Data? {
        guard let source = CGImageSourceCreateWithData(sourceData as CFData, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: 1_200,
            kCGImageSourceShouldCacheImmediately: true
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        let destinationData = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            destinationData,
            UTType.jpeg.identifier as CFString,
            1,
            nil
        ) else { return nil }
        CGImageDestinationAddImage(
            destination,
            image,
            [kCGImageDestinationLossyCompressionQuality: 0.8] as CFDictionary
        )
        guard CGImageDestinationFinalize(destination) else { return nil }
        return destinationData as Data
    }
}
