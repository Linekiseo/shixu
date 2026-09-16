import AppKit
import Foundation

@MainActor
final class ScreenshotService {
    static let shared = ScreenshotService()

    func captureInteractive(completion: @escaping @MainActor () -> Void) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        process.arguments = ["-i", "-c"]
        process.terminationHandler = { process in
            guard process.terminationStatus == 0 else { return }
            Task { @MainActor in completion() }
        }
        try? process.run()
    }
}
