import Foundation

struct ClipboardCandidate: Equatable {
    var kind: CaptureKind
    var displayText: String
    var text: String?
    var imageData: Data?
    var fileURL: URL?
    var sourceApplication: String? = nil
    var detectedAt: Date = .now
}
