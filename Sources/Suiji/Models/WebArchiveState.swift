import Foundation

enum WebArchiveState: String, Codable, Sendable {
    case queued
    case capturing
    case archived
    case loginRequired
    case failed
}

enum WebArchiveAccessDecision: Equatable {
    case archive
    case loginRequired
    case failedStatus(Int)
}

enum WebArchiveAccessPolicy {
    static func decision(
        statusCode: Int?,
        looksLikeLogin: Bool,
        looksLikePrivateMissingPage: Bool
    ) -> WebArchiveAccessDecision {
        if statusCode == 401 || statusCode == 403 || looksLikeLogin {
            return .loginRequired
        }
        if statusCode == 404, looksLikePrivateMissingPage {
            return .loginRequired
        }
        if let statusCode, statusCode >= 400 {
            return .failedStatus(statusCode)
        }
        return .archive
    }
}

enum WebsiteIdentity {
    private static let multipartPublicSuffixes: Set<String> = [
        "co.uk", "org.uk", "ac.uk",
        "com.cn", "net.cn", "org.cn",
        "com.au", "net.au", "org.au",
        "co.jp", "co.kr", "com.hk", "com.tw"
    ]

    static func rootDomain(for url: URL) -> String? {
        guard let rawHost = url.host(percentEncoded: false)?.lowercased() else { return nil }
        let host = rawHost.hasPrefix("www.") ? String(rawHost.dropFirst(4)) : rawHost
        if host == "localhost" || host.split(separator: ".").allSatisfy({ $0.allSatisfy(\.isNumber) }) {
            return host
        }
        let parts = host.split(separator: ".").map(String.init)
        guard parts.count > 2 else { return host }
        let lastTwo = parts.suffix(2).joined(separator: ".")
        if multipartPublicSuffixes.contains(lastTwo), parts.count >= 3 {
            return parts.suffix(3).joined(separator: ".")
        }
        return lastTwo
    }

    static func rootURL(for url: URL) -> URL {
        guard let rootDomain = rootDomain(for: url),
              let scheme = url.scheme,
              let root = URL(string: "\(scheme)://\(rootDomain)") else { return url }
        return root
    }
}
