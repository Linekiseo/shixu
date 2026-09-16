import Foundation

@MainActor
final class CaptureRuntimeController: ObservableObject {
    static let shared = CaptureRuntimeController()

    @Published private(set) var isCaptureEnabled: Bool

    private let defaults: UserDefaults
    private weak var store: CaptureStore?
    private var hasStarted = false

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        isCaptureEnabled = defaults.object(forKey: "ambientCaptureEnabled") as? Bool ?? true
    }

    func start(store: CaptureStore) {
        self.store = store
        hasStarted = true
        let persistedValue = defaults.object(forKey: "ambientCaptureEnabled") as? Bool ?? true
        if isCaptureEnabled != persistedValue {
            isCaptureEnabled = persistedValue
        }
        applyCaptureState()
    }

    func setCaptureEnabled(_ enabled: Bool) {
        guard isCaptureEnabled != enabled else { return }
        isCaptureEnabled = enabled
        defaults.set(enabled, forKey: "ambientCaptureEnabled")
        applyCaptureState()
    }

    func toggleCapture() {
        setCaptureEnabled(!isCaptureEnabled)
    }

    func shutdown() {
        ClipboardMonitor.shared.stop()
        FolderMonitorService.shared.stop()
        hasStarted = false
        store = nil
    }

    private func applyCaptureState() {
        guard hasStarted, let store else { return }
        if isCaptureEnabled {
            ClipboardMonitor.shared.start(store: store)
            FolderMonitorService.shared.start(store: store)
        } else {
            ClipboardMonitor.shared.stop()
            FolderMonitorService.shared.stop()
        }
    }
}
