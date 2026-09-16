import AppKit
import Foundation

@MainActor
final class ClipboardMonitor {
    static let shared = ClipboardMonitor()

    private var timer: Timer?
    private var lastChangeCount = NSPasteboard.general.changeCount

    var isRunning: Bool { timer != nil }

    func start(store: CaptureStore) {
        guard timer == nil else { return }
        lastChangeCount = NSPasteboard.general.changeCount
        timer = Timer.scheduledTimer(withTimeInterval: 0.8, repeats: true) { _ in
            MainActor.assumeIsolated {
                self.poll(store: store)
            }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        lastChangeCount = NSPasteboard.general.changeCount
    }

    func poll(store: CaptureStore, force: Bool = false) {
        let pasteboard = NSPasteboard.general
        guard force || pasteboard.changeCount != lastChangeCount else { return }
        lastChangeCount = pasteboard.changeCount
        let sourceApplication = NSWorkspace.shared.frontmostApplication?.localizedName
        let ownApplicationNames = [AppBrand.displayName, AppBrand.legacyDisplayName, "Suiji"]
        guard force || !ownApplicationNames.contains(sourceApplication ?? "") else { return }

        if let imageData = pasteboard.data(forType: .png) ?? pasteboard.data(forType: .tiff) {
            let candidate = ClipboardCandidate(kind: .image, displayText: "剪贴板中的图片", text: nil, imageData: imageData, fileURL: nil, sourceApplication: sourceApplication)
            store.receive(candidate: candidate)
            return
        }

        if let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: nil) as? [URL], let first = urls.first, first.isFileURL {
            let kind = ContentDetector.kind(for: first)
            let candidate = ClipboardCandidate(kind: kind, displayText: first.lastPathComponent, text: nil, imageData: nil, fileURL: first, sourceApplication: sourceApplication)
            store.receive(candidate: candidate)
            return
        }

        if let rawText = pasteboard.string(forType: .string) {
            let text = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { return }
            if !text.contains("\n") {
                let possibleFile = URL(fileURLWithPath: text)
                if let values = try? possibleFile.resourceValues(forKeys: [.isRegularFileKey]), values.isRegularFile == true {
                    let kind = ContentDetector.kind(for: possibleFile)
                    let candidate = ClipboardCandidate(
                        kind: kind,
                        displayText: possibleFile.lastPathComponent,
                        text: nil,
                        imageData: nil,
                        fileURL: possibleFile,
                        sourceApplication: sourceApplication
                    )
                    store.receive(candidate: candidate)
                    return
                }
            }

            let kind = ContentDetector.inferredKind(for: text)
            let display: String
            switch kind {
            case .credential:
                if let apiKey = LLMAPIKeyDetector.detect(in: text) {
                    display = "\(apiKey.provider ?? "LLM") API 密钥（内容已隐藏）"
                } else {
                    display = "检测到账号信息（内容已隐藏）"
                }
            case .web:
                display = URL(string: text)?.host(percentEncoded: false) ?? "网页链接"
            default:
                if let format = TextFormatDetector.detect(text) {
                    display = "\(format.title) · \(text.count) 字 · 将保存为 .\(format.fileExtension)"
                } else {
                    display = "复制的文字 · \(text.count) 字"
                }
            }
            let candidate = ClipboardCandidate(kind: kind, displayText: display, text: rawText, imageData: nil, fileURL: nil, sourceApplication: sourceApplication)
            store.receive(candidate: candidate)
        }
    }
}
