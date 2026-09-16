import Foundation

enum SearchDateScope: String, CaseIterable, Identifiable {
    case all
    case today
    case week
    case month

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: "全部时间"
        case .today: "今天"
        case .week: "近 7 天"
        case .month: "近 30 天"
        }
    }

    func includes(_ date: Date, now: Date = .now) -> Bool {
        let calendar = Calendar.current
        switch self {
        case .all:
            return true
        case .today:
            return calendar.isDate(date, inSameDayAs: now)
        case .week:
            return date >= calendar.date(byAdding: .day, value: -7, to: now) ?? .distantPast
        case .month:
            return date >= calendar.date(byAdding: .day, value: -30, to: now) ?? .distantPast
        }
    }
}

enum SearchKindScope: String, CaseIterable, Identifiable {
    case all
    case text
    case image
    case web
    case credential
    case file

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: "全部"
        case .text: "文字"
        case .image: "图片"
        case .web: "网页"
        case .credential: "账号"
        case .file: "文件"
        }
    }

    var systemImage: String {
        switch self {
        case .all: "square.grid.2x2"
        case .text: CaptureKind.text.systemImage
        case .image: CaptureKind.image.systemImage
        case .web: CaptureKind.web.systemImage
        case .credential: CaptureKind.credential.systemImage
        case .file: CaptureKind.file.systemImage
        }
    }

    func includes(_ item: CaptureItem) -> Bool {
        self == .all || item.kind.rawValue == rawValue
    }
}
