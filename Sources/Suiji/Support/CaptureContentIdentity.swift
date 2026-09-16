import CryptoKit
import Foundation

enum CaptureContentIdentity {
    static func normalizedText(_ text: String) -> String {
        text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func textFingerprint(_ text: String) -> String {
        fingerprint(Data(normalizedText(text).utf8))
    }

    static func dataFingerprint(_ data: Data) -> String {
        fingerprint(data)
    }

    private static func fingerprint(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
