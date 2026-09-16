import AppKit
import SwiftUI

@MainActor
final class PreviewWindowController {
    static let shared = PreviewWindowController()
    private var controllers: [String: NSWindowController] = [:]

    func showImage(url: URL, title: String) {
        show(key: "image:\(url.path)", title: title, minimumSize: NSSize(width: 680, height: 480)) { close in
            ImagePreviewSheet(url: url, title: title, onClose: close)
        }
    }

    func showFile(url: URL, item: CaptureItem) {
        show(key: "file:\(url.path)", title: item.title, minimumSize: NSSize(width: 720, height: 520)) { close in
            FilePreviewSheet(url: url, item: item, onClose: close)
        }
    }

    private func show<Content: View>(
        key: String,
        title: String,
        minimumSize: NSSize,
        @ViewBuilder content: (@escaping () -> Void) -> Content
    ) {
        if let existing = controllers[key], let window = existing.window {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: max(900, minimumSize.width), height: max(680, minimumSize.height)),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = title
        window.minSize = minimumSize
        window.isReleasedWhenClosed = false
        let controller = NSWindowController(window: window)
        controllers[key] = controller
        window.contentView = NSHostingView(rootView: content { [weak window] in window?.close() })
        window.center()
        controller.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
