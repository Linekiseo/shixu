import AppKit
import SwiftUI

@MainActor
final class SearchPanelController {
    static let shared = SearchPanelController()

    private var panel: NSPanel?

    func show() {
        let panel = panel ?? makePanel()
        position(panel)
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
    }

    func hide() {
        panel?.orderOut(nil)
    }

    func reveal(_ item: CaptureItem) {
        CaptureStore.shared.revealInAll(item.id)
        hide()
        NSApp.activate(ignoringOtherApps: true)
        NSApp.windows
            .first(where: { !($0 is NSPanel) && $0.title == AppBrand.displayName })?
            .makeKeyAndOrderFront(nil)
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 780, height: 600),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.title = "搜索\(AppBrand.displayName)"
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isReleasedWhenClosed = false
        panel.contentView = NSHostingView(rootView: SearchPanelView(store: .shared))
        self.panel = panel
        return panel
    }

    private func position(_ panel: NSPanel) {
        let screen = NSScreen.main ?? NSScreen.screens.first
        guard let visibleFrame = screen?.visibleFrame else { return }
        panel.setFrameOrigin(NSPoint(
            x: visibleFrame.midX - panel.frame.width / 2,
            y: visibleFrame.maxY - panel.frame.height - 112
        ))
    }
}
