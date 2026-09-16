import AppKit
import SwiftUI

@MainActor
final class DockMenuController: NSObject {
    static let shared = DockMenuController()

    private weak var store: CaptureStore?
    private var runtime: CaptureRuntimeController?
    private var openMainWindowHandler: (() -> Void)?
    private var openSettingsHandler: (() -> Void)?

    func configureWindowActions(
        openMainWindow: @escaping () -> Void,
        openSettings: @escaping () -> Void
    ) {
        openMainWindowHandler = openMainWindow
        openSettingsHandler = openSettings
    }

    func makeMenu(store: CaptureStore, runtime: CaptureRuntimeController) -> NSMenu {
        self.store = store
        self.runtime = runtime

        let menu = NSMenu(title: AppBrand.displayName)
        menu.autoenablesItems = false
        let isActive = runtime.isCaptureEnabled

        let status = NSMenuItem(
            title: isActive ? "●  正在后台收集" : "○  后台收集已暂停",
            action: nil,
            keyEquivalent: ""
        )
        status.isEnabled = false
        status.image = symbolImage(isActive ? "waveform.path.ecg" : "pause.circle")
        menu.addItem(status)

        menu.addItem(actionItem(
            title: isActive ? "暂停后台收集" : "开始后台收集",
            symbol: isActive ? "pause.fill" : "play.fill",
            action: #selector(toggleCapture)
        ))

        let rules = NSMenuItem(title: "收集规则", action: nil, keyEquivalent: "")
        rules.image = symbolImage("slider.horizontal.3")
        rules.submenu = captureRulesMenu()
        menu.addItem(rules)

        menu.addItem(.separator())
        menu.addItem(actionItem(title: "快速记录…", symbol: "square.and.pencil", action: #selector(showQuickCapture)))
        menu.addItem(actionItem(title: "保存当前剪贴板", symbol: "doc.on.clipboard", action: #selector(saveCurrentClipboard)))
        menu.addItem(actionItem(title: "交互式截屏", symbol: "viewfinder", action: #selector(captureScreenshot)))
        menu.addItem(actionItem(title: "搜索资料库…", symbol: "magnifyingglass", action: #selector(showSearch)))

        if let recentMenu = recentRecordsMenu() {
            let recent = NSMenuItem(title: "最近记录", action: nil, keyEquivalent: "")
            recent.image = symbolImage("clock.arrow.circlepath")
            recent.submenu = recentMenu
            menu.addItem(recent)
        }

        menu.addItem(.separator())
        menu.addItem(actionItem(title: "打开\(AppBrand.displayName)", symbol: "macwindow", action: #selector(openMainWindow)))
        menu.addItem(actionItem(title: "设置…", symbol: "gearshape", action: #selector(openSettings)))
        return menu
    }

    private func captureRulesMenu() -> NSMenu {
        let menu = NSMenu(title: "收集规则")
        menu.autoenablesItems = false

        let clipboard = actionItem(
            title: "剪贴板变化自动归档",
            symbol: "doc.on.clipboard",
            action: #selector(toggleClipboardAutoCapture)
        )
        clipboard.state = UserDefaults.standard.bool(forKey: "autoCaptureClipboard") ? .on : .off
        menu.addItem(clipboard)

        let folders = actionItem(
            title: "文件夹变化自动归档",
            symbol: "folder.badge.gearshape",
            action: #selector(toggleFolderAutoCapture)
        )
        folders.state = UserDefaults.standard.bool(forKey: "autoIndexWatchedFolders") ? .on : .off
        menu.addItem(folders)

        menu.addItem(.separator())
        let hint = NSMenuItem(title: "暂停后不读取新的系统变化", action: nil, keyEquivalent: "")
        hint.isEnabled = false
        menu.addItem(hint)
        return menu
    }

    private func recentRecordsMenu() -> NSMenu? {
        guard let store else { return nil }
        let items = store.items
            .filter { !$0.isDeleted }
            .sorted { $0.createdAt > $1.createdAt }
            .prefix(5)
        guard !items.isEmpty else { return nil }

        let menu = NSMenu(title: "最近记录")
        menu.autoenablesItems = false
        for item in items {
            let entry = actionItem(
                title: shortTitle(item.title),
                symbol: item.kind.systemImage,
                action: #selector(openRecentRecord(_:))
            )
            entry.representedObject = item.id.uuidString
            menu.addItem(entry)
        }
        return menu
    }

    private func actionItem(title: String, symbol: String, action: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        item.image = symbolImage(symbol)
        item.isEnabled = true
        return item
    }

    private func symbolImage(_ name: String) -> NSImage? {
        let image = NSImage(systemSymbolName: name, accessibilityDescription: nil)
        image?.isTemplate = true
        return image
    }

    private func shortTitle(_ title: String) -> String {
        title.count <= 30 ? title : String(title.prefix(27)) + "…"
    }

    @objc private func toggleCapture() {
        runtime?.toggleCapture()
    }

    @objc private func toggleClipboardAutoCapture() {
        let defaults = UserDefaults.standard
        defaults.set(!defaults.bool(forKey: "autoCaptureClipboard"), forKey: "autoCaptureClipboard")
    }

    @objc private func toggleFolderAutoCapture() {
        let defaults = UserDefaults.standard
        defaults.set(!defaults.bool(forKey: "autoIndexWatchedFolders"), forKey: "autoIndexWatchedFolders")
    }

    @objc private func showQuickCapture() {
        QuickCapturePanelController.shared.show()
    }

    @objc private func saveCurrentClipboard() {
        store?.importCurrentClipboard()
    }

    @objc private func captureScreenshot() {
        guard let store else { return }
        ScreenshotService.shared.captureInteractive {
            store.importCurrentClipboard()
        }
    }

    @objc private func showSearch() {
        SearchPanelController.shared.show()
    }

    @objc private func openRecentRecord(_ sender: NSMenuItem) {
        guard let identifier = sender.representedObject as? String,
              let itemID = UUID(uuidString: identifier) else { return }
        store?.revealInAll(itemID)
        openMainWindow()
    }

    @objc private func openMainWindow() {
        if let openMainWindowHandler {
            openMainWindowHandler()
        } else {
            NSApp.activate(ignoringOtherApps: true)
            NSApp.windows.first(where: \.canBecomeMain)?.makeKeyAndOrderFront(nil)
        }
    }

    @objc private func openSettings() {
        if let openSettingsHandler {
            openSettingsHandler()
        } else {
            NSApp.activate(ignoringOtherApps: true)
            NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
        }
    }
}

struct DockMenuWindowBridge: View {
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .onAppear {
                DockMenuController.shared.configureWindowActions(
                    openMainWindow: {
                        openWindow(id: "main")
                        NSApp.activate(ignoringOtherApps: true)
                    },
                    openSettings: {
                        openSettings()
                        NSApp.activate(ignoringOtherApps: true)
                    }
                )
            }
    }
}
