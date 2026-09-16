import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        UserDefaults.standard.register(defaults: [
            "ambientCaptureEnabled": true,
            "autoCaptureClipboard": true,
            "autoIndexWatchedFolders": true,
            "fileStorageMode": FileStorageMode.linked.rawValue,
            "deepSeekAISearchBaseURL": DeepSeekAISearchService.defaultBaseURL
        ])
        NSApp.setActivationPolicy(.regular)
        SystemServicesProvider.register()
        Task { @MainActor in
            await Task.yield()
            CaptureRuntimeController.shared.start(store: .shared)
        }
        GlobalHotKeyService.shared.register {
            QuickCapturePanelController.shared.show()
        }
        DispatchQueue.main.async {
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        GlobalHotKeyService.shared.unregister()
        CaptureRuntimeController.shared.shutdown()
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        Task { @MainActor in
            await Task.yield()
            CaptureStore.shared.synchronizeGeneratedTextFiles()
        }
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        urls.forEach(SuijiURLHandler.handle)
    }

    func applicationDockMenu(_ sender: NSApplication) -> NSMenu? {
        DockMenuController.shared.makeMenu(store: .shared, runtime: .shared)
    }
}

@main
struct SuijiApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var store = CaptureStore.shared
    @StateObject private var runtime = CaptureRuntimeController.shared

    var body: some Scene {
        WindowGroup(AppBrand.displayName, id: "main") {
            ContentView(store: store)
                .background(DockMenuWindowBridge())
        }
        .defaultSize(width: 1280, height: 820)
        .commands {
            CommandMenu(AppBrand.displayName) {
                Button(runtime.isCaptureEnabled ? "暂停后台收集" : "开始后台收集") {
                    runtime.toggleCapture()
                }
                .keyboardShortcut("p", modifiers: [.command, .option])
                Divider()
                Button("快速记录…") { QuickCapturePanelController.shared.show() }
                Button("搜索资料库…") { SearchPanelController.shared.show() }
                    .keyboardShortcut("k", modifiers: .command)
                Button("保存当前剪贴板") { store.importCurrentClipboard() }
                    .keyboardShortcut("v", modifiers: [.command, .shift])
                Button("交互式截屏") {
                    ScreenshotService.shared.captureInteractive { store.importCurrentClipboard() }
                }
            }
        }

        Settings {
            SettingsView()
                .background(DockMenuWindowBridge())
        }
    }
}
