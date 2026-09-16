import Foundation

enum CaptureKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case text
    case image
    case web
    case credential
    case file

    var id: String { rawValue }

    var title: String {
        switch self {
        case .text: "文字"
        case .image: "图片与截图"
        case .web: "网页"
        case .credential: "账号"
        case .file: "文件"
        }
    }

    var systemImage: String {
        switch self {
        case .text: "text.alignleft"
        case .image: "photo"
        case .web: "globe"
        case .credential: "lock"
        case .file: "doc"
        }
    }
}

enum CaptureSecurityLevel: String, Codable, Sendable {
    case standard
    case sensitive

    var title: String { self == .sensitive ? "敏感" : "普通" }
}

enum CredentialRecordType: String, Codable, CaseIterable, Identifiable, Sendable {
    case account
    case apiKey

    var id: String { rawValue }

    var title: String {
        switch self {
        case .account: "网站账号"
        case .apiKey: "LLM API 密钥"
        }
    }
}

enum CaptureCompositionKind: String, Codable, Sendable {
    case llmAPI
    case videoGroup
    case related

    var title: String {
        switch self {
        case .llmAPI: "LLM API 配置"
        case .videoGroup: "视频组合"
        case .related: "关联组合"
        }
    }

    var systemImage: String {
        switch self {
        case .llmAPI: "key.viewfinder"
        case .videoGroup: "play.rectangle.on.rectangle"
        case .related: "square.stack.3d.up.fill"
        }
    }
}

struct CaptureItem: Identifiable, Codable, Hashable, Sendable {
    let id: UUID
    var createdAt: Date
    var kind: CaptureKind
    var title: String
    var body: String
    var source: String
    var sourceApplication: String?
    var tags: [String]
    var summary: String
    var textFormat: TextContentFormat?
    var attachmentPath: String?
    var fileName: String?
    var username: String?
    var secretKey: String?
    var credentialType: CredentialRecordType?
    var platform: String?
    var domain: String?
    var webRootDomain: String?
    var webArchiveState: WebArchiveState?
    var webArchivePath: String?
    var webArchiveCapturedAt: Date?
    var webArchiveOriginalSize: Int64?
    var webArchiveCompressedSize: Int64?
    var webArchiveMessage: String?
    var loginURL: String?
    var apiBaseURL: String?
    var originalLocation: String?
    var fileSize: Int64?
    var fileExtension: String?
    var fileBookmark: Data?
    var backupPath: String?
    var backupOriginalSize: Int64?
    var backupCompressedSize: Int64?
    var contentFingerprint: String?
    var collection: String?
    var organizationReason: String?
    var userNote: String?
    var securityLevel: CaptureSecurityLevel?
    var needsReview: Bool?
    var compositionID: UUID?
    var compositionKind: CaptureCompositionKind?
    var compositionTitle: String?
    var compositionOrder: Int?
    var isFavorite: Bool
    var isDeleted: Bool

    init(
        id: UUID = UUID(),
        createdAt: Date = .now,
        kind: CaptureKind,
        title: String,
        body: String = "",
        source: String,
        sourceApplication: String? = nil,
        tags: [String] = [],
        summary: String = "",
        textFormat: TextContentFormat? = nil,
        attachmentPath: String? = nil,
        fileName: String? = nil,
        username: String? = nil,
        secretKey: String? = nil,
        credentialType: CredentialRecordType? = nil,
        platform: String? = nil,
        domain: String? = nil,
        webRootDomain: String? = nil,
        webArchiveState: WebArchiveState? = nil,
        webArchivePath: String? = nil,
        webArchiveCapturedAt: Date? = nil,
        webArchiveOriginalSize: Int64? = nil,
        webArchiveCompressedSize: Int64? = nil,
        webArchiveMessage: String? = nil,
        loginURL: String? = nil,
        apiBaseURL: String? = nil,
        originalLocation: String? = nil,
        fileSize: Int64? = nil,
        fileExtension: String? = nil,
        fileBookmark: Data? = nil,
        backupPath: String? = nil,
        backupOriginalSize: Int64? = nil,
        backupCompressedSize: Int64? = nil,
        contentFingerprint: String? = nil,
        collection: String? = nil,
        organizationReason: String? = nil,
        userNote: String? = nil,
        securityLevel: CaptureSecurityLevel? = nil,
        needsReview: Bool? = nil,
        compositionID: UUID? = nil,
        compositionKind: CaptureCompositionKind? = nil,
        compositionTitle: String? = nil,
        compositionOrder: Int? = nil,
        isFavorite: Bool = false,
        isDeleted: Bool = false
    ) {
        self.id = id
        self.createdAt = createdAt
        self.kind = kind
        self.title = title
        self.body = body
        self.source = source
        self.sourceApplication = sourceApplication
        self.tags = tags
        self.summary = summary
        self.textFormat = textFormat
        self.attachmentPath = attachmentPath
        self.fileName = fileName
        self.username = username
        self.secretKey = secretKey
        self.credentialType = credentialType
        self.platform = platform
        self.domain = domain
        self.webRootDomain = webRootDomain
        self.webArchiveState = webArchiveState
        self.webArchivePath = webArchivePath
        self.webArchiveCapturedAt = webArchiveCapturedAt
        self.webArchiveOriginalSize = webArchiveOriginalSize
        self.webArchiveCompressedSize = webArchiveCompressedSize
        self.webArchiveMessage = webArchiveMessage
        self.loginURL = loginURL
        self.apiBaseURL = apiBaseURL
        self.originalLocation = originalLocation
        self.fileSize = fileSize
        self.fileExtension = fileExtension
        self.fileBookmark = fileBookmark
        self.backupPath = backupPath
        self.backupOriginalSize = backupOriginalSize
        self.backupCompressedSize = backupCompressedSize
        self.contentFingerprint = contentFingerprint
        self.collection = collection
        self.organizationReason = organizationReason
        self.userNote = userNote
        self.securityLevel = securityLevel
        self.needsReview = needsReview
        self.compositionID = compositionID
        self.compositionKind = compositionKind
        self.compositionTitle = compositionTitle
        self.compositionOrder = compositionOrder
        self.isFavorite = isFavorite
        self.isDeleted = isDeleted
    }
}
