import AppKit
import Foundation

@MainActor
enum CapturePrimaryAction {
    static func perform(store: CaptureStore, item: CaptureItem) {
        switch item.kind {
        case .file:
            if let url = store.attachmentURL(for: item) { NSWorkspace.shared.open(url) }
        case .image:
            if let url = store.attachmentURL(for: item) {
                PreviewWindowController.shared.showImage(url: url, title: item.title)
            }
        case .web:
            if let url = URL(string: item.body) { NSWorkspace.shared.open(url) }
        case .credential:
            let value = item.credentialType == .apiKey ? item.apiBaseURL : item.loginURL
            if let value, let url = URL(string: value) { NSWorkspace.shared.open(url) }
        case .text:
            if item.textFormat != nil, let url = store.attachmentURL(for: item) {
                NSWorkspace.shared.open(url)
            }
        }
    }

    static func preview(store: CaptureStore, item: CaptureItem) {
        guard let url = store.attachmentURL(for: item) else { return }
        if item.kind == .image {
            PreviewWindowController.shared.showImage(url: url, title: item.title)
        } else {
            PreviewWindowController.shared.showFile(url: url, item: item)
        }
    }
}
