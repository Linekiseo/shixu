import AppKit
import Foundation

@MainActor
final class SystemServicesProvider: NSObject {
    static let shared = SystemServicesProvider()

    private static let legacyFileNamesType = NSPasteboard.PasteboardType("NSFilenamesPboardType")

    static func register() {
        NSApp.servicesProvider = shared
        NSUpdateDynamicServices()
    }

    @objc(captureToSuiji:userData:error:)
    func captureToSuiji(
        _ pasteboard: NSPasteboard,
        userData: String?,
        error: AutoreleasingUnsafeMutablePointer<NSString?>
    ) {
        let urls = Self.fileURLs(from: pasteboard)
        guard !urls.isEmpty else {
            error.pointee = "\(AppBrand.displayName)没有从当前选择中读到文件或文件夹。" as NSString
            return
        }

        let sourceApplication = Self.sourceApplicationName()
        for (index, url) in urls.enumerated() {
            CaptureStore.shared.capture(
                fileURL: url,
                source: "访达右键",
                sourceApplication: sourceApplication,
                silent: index < urls.count - 1
            )
        }
    }

    static func fileURLs(from pasteboard: NSPasteboard) -> [URL] {
        var output: [URL] = []
        var seenPaths = Set<String>()

        func append(_ url: URL) {
            let normalized = url.standardizedFileURL
            guard normalized.isFileURL, seenPaths.insert(normalized.path).inserted else { return }
            output.append(normalized)
        }

        if let urls = pasteboard.readObjects(
            forClasses: [NSURL.self],
            options: [.urlReadingFileURLsOnly: true]
        ) as? [URL] {
            urls.forEach(append)
        }

        if let paths = pasteboard.propertyList(forType: legacyFileNamesType) as? [String] {
            paths.map { URL(fileURLWithPath: $0) }.forEach(append)
        }

        if let value = pasteboard.string(forType: .fileURL), let url = URL(string: value) {
            append(url)
        }

        return output
    }

    private static func sourceApplicationName() -> String? {
        guard let application = NSWorkspace.shared.frontmostApplication,
              application.bundleIdentifier != Bundle.main.bundleIdentifier else { return nil }
        return application.localizedName
    }
}

enum SuijiURLHandler {
    @MainActor
    static func handle(_ url: URL) {
        guard url.scheme == "suiji", url.host == "capture" else { return }
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        if let text = components?.queryItems?.first(where: { $0.name == "text" })?.value, !text.isEmpty {
            CaptureStore.shared.capture(text: text, source: "\(AppBrand.displayName) URL")
        } else if let value = components?.queryItems?.first(where: { $0.name == "url" })?.value, !value.isEmpty {
            CaptureStore.shared.capture(text: value, forcedKind: .web, source: "\(AppBrand.displayName) URL")
        }
    }
}
