import Foundation

enum SystemSignalSource: String, Sendable {
    case clipboard
    case watchedFolder
    case macOSService
    case screenshot

    var title: String {
        switch self {
        case .clipboard: "剪贴板"
        case .watchedFolder: "监测文件夹"
        case .macOSService: "系统服务"
        case .screenshot: "系统截屏"
        }
    }

    var systemImage: String {
        switch self {
        case .clipboard: "doc.on.clipboard"
        case .watchedFolder: "folder.badge.gearshape"
        case .macOSService: "gearshape.2"
        case .screenshot: "viewfinder"
        }
    }
}

enum SystemSignalState: String, Sendable {
    case pending
    case captured
    case ignored
}

struct SystemSignal: Identifiable, Equatable {
    let id: UUID
    var source: SystemSignalSource
    var kind: CaptureKind
    var title: String
    var detail: String
    var sourceApplication: String?
    var createdAt: Date
    var state: SystemSignalState
    var candidate: ClipboardCandidate?
    var fileURL: URL?

    init(
        id: UUID = UUID(),
        source: SystemSignalSource,
        kind: CaptureKind,
        title: String,
        detail: String,
        sourceApplication: String? = nil,
        createdAt: Date = .now,
        state: SystemSignalState = .pending,
        candidate: ClipboardCandidate? = nil,
        fileURL: URL? = nil
    ) {
        self.id = id
        self.source = source
        self.kind = kind
        self.title = title
        self.detail = detail
        self.sourceApplication = sourceApplication
        self.createdAt = createdAt
        self.state = state
        self.candidate = candidate
        self.fileURL = fileURL
    }
}

struct SystemSignalTimelineSection: Identifiable {
    let id: Date
    let day: Date
    let signals: [SystemSignal]

    var title: String {
        let calendar = Calendar.current
        if calendar.isDateInToday(day) { return "今天" }
        if calendar.isDateInYesterday(day) { return "昨天" }
        return day.formatted(.dateTime.year().month().day())
    }

    var timeRange: String {
        guard let newest = signals.first?.createdAt else { return "" }
        guard let oldest = signals.last?.createdAt, oldest != newest else { return newest.suijiTime }
        return "\(oldest.suijiTime) – \(newest.suijiTime)"
    }

    static func sections(from signals: [SystemSignal]) -> [SystemSignalTimelineSection] {
        let sorted = signals.sorted { $0.createdAt > $1.createdAt }
        let calendar = Calendar.current
        let grouped = Dictionary(grouping: sorted) { calendar.startOfDay(for: $0.createdAt) }
        return grouped.keys.sorted(by: >).map { day in
            SystemSignalTimelineSection(id: day, day: day, signals: grouped[day] ?? [])
        }
    }
}

struct WatchedFolder: Identifiable, Codable, Hashable, Sendable {
    var id: UUID
    var path: String
    var addedAt: Date
    var isEnabled: Bool

    init(id: UUID = UUID(), path: String, addedAt: Date = .now, isEnabled: Bool = true) {
        self.id = id
        self.path = path
        self.addedAt = addedAt
        self.isEnabled = isEnabled
    }

    var url: URL { URL(fileURLWithPath: path, isDirectory: true) }
    var displayName: String { url.lastPathComponent }
}
