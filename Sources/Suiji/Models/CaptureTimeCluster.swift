import Foundation

enum CaptureCalendarLevel: String, CaseIterable, Identifiable {
    case year
    case month
    case week
    case day

    var id: String { rawValue }

    var title: String {
        switch self {
        case .year: "年"
        case .month: "月"
        case .week: "周"
        case .day: "日"
        }
    }

    var systemImage: String {
        switch self {
        case .year: "square.grid.3x3"
        case .month: "calendar"
        case .week: "calendar.day.timeline.left"
        case .day: "clock"
        }
    }

    var calendarComponent: Calendar.Component {
        switch self {
        case .year: .year
        case .month: .month
        case .week: .weekOfYear
        case .day: .day
        }
    }
}

struct CaptureCalendarPage: Equatable {
    let level: CaptureCalendarLevel
    let anchor: Date

    static var calendar: Calendar {
        var calendar = Calendar.current
        calendar.firstWeekday = 2
        calendar.minimumDaysInFirstWeek = 4
        return calendar
    }

    var interval: DateInterval {
        Self.calendar.dateInterval(of: level.calendarComponent, for: anchor)
            ?? DateInterval(start: Self.calendar.startOfDay(for: anchor), duration: 24 * 60 * 60)
    }

    var title: String {
        let calendar = Self.calendar
        let components = calendar.dateComponents([.year, .month, .day], from: anchor)
        switch level {
        case .year:
            return "\(components.year ?? 0)年"
        case .month:
            return "\(components.year ?? 0)年\(components.month ?? 0)月"
        case .week:
            let end = calendar.date(byAdding: .day, value: -1, to: interval.end) ?? interval.end
            let startParts = calendar.dateComponents([.year, .month, .day], from: interval.start)
            let endParts = calendar.dateComponents([.year, .month, .day], from: end)
            if startParts.year == endParts.year {
                return "\(startParts.year ?? 0)年 \(startParts.month ?? 0)月\(startParts.day ?? 0)日 – \(endParts.month ?? 0)月\(endParts.day ?? 0)日"
            }
            return "\(startParts.year ?? 0)年\(startParts.month ?? 0)月\(startParts.day ?? 0)日 – \(endParts.year ?? 0)年\(endParts.month ?? 0)月\(endParts.day ?? 0)日"
        case .day:
            return CaptureTimelineSection.title(for: anchor)
        }
    }

    var detail: String {
        switch level {
        case .year: "全年"
        case .month: "月历"
        case .week: "第 \(Self.calendar.component(.weekOfYear, from: anchor)) 周"
        case .day: CaptureTimelineSection.dateDetail(for: anchor)
        }
    }

    func shifted(by value: Int) -> Date {
        Self.calendar.date(byAdding: level.calendarComponent, value: value, to: anchor) ?? anchor
    }

    func contains(_ date: Date) -> Bool {
        interval.contains(date)
    }

    var days: [Date] {
        var output: [Date] = []
        var cursor = interval.start
        while cursor < interval.end {
            output.append(cursor)
            guard let next = Self.calendar.date(byAdding: .day, value: 1, to: cursor) else { break }
            cursor = next
        }
        return output
    }

    var monthGridDays: [Date] {
        guard level == .month,
              let monthInterval = Self.calendar.dateInterval(of: .month, for: anchor),
              let firstWeek = Self.calendar.dateInterval(of: .weekOfYear, for: monthInterval.start),
              let lastVisibleDay = Self.calendar.date(byAdding: .day, value: -1, to: monthInterval.end),
              let lastWeek = Self.calendar.dateInterval(of: .weekOfYear, for: lastVisibleDay) else {
            return days
        }

        var output: [Date] = []
        var cursor = firstWeek.start
        while cursor < lastWeek.end {
            output.append(cursor)
            guard let next = Self.calendar.date(byAdding: .day, value: 1, to: cursor) else { break }
            cursor = next
        }
        return output
    }
}

struct CaptureTimeCluster: Identifiable, Equatable {
    let id: UUID
    let day: Date
    let startDate: Date
    let endDate: Date
    let items: [CaptureItem]

    var title: String {
        let sources = items.compactMap(\.sourceApplication)
        let dominant = Dictionary(grouping: sources, by: { $0 }).max { $0.value.count < $1.value.count }?.key
        if let dominant { return "\(dominant) 中的一段记录" }
        if let collection = items.compactMap(\.collection).first { return "\(collection)时间片段" }
        return "随手记录片段"
    }

    var timeRange: String {
        startDate == endDate ? startDate.suijiTime : "\(startDate.suijiTime) – \(endDate.suijiTime)"
    }

    var typeSummary: String {
        Dictionary(grouping: items, by: \.kind)
            .sorted { $0.value.count > $1.value.count }
            .map { "\($0.key.title) \($0.value.count)" }
            .joined(separator: " · ")
    }

    static func clusters(from input: [CaptureItem], maximumGap: TimeInterval = 45 * 60) -> [CaptureTimeCluster] {
        let calendar = Calendar.current
        let grouped = Dictionary(grouping: input.filter { !$0.isDeleted }) {
            calendar.startOfDay(for: $0.createdAt)
        }
        var output: [CaptureTimeCluster] = []
        for day in grouped.keys.sorted(by: >) {
            let sorted = (grouped[day] ?? []).sorted { $0.createdAt < $1.createdAt }
            var session: [CaptureItem] = []
            func emit() {
                guard let first = session.first, let last = session.last else { return }
                output.append(CaptureTimeCluster(
                    id: last.id,
                    day: day,
                    startDate: first.createdAt,
                    endDate: last.createdAt,
                    items: session.reversed()
                ))
            }
            for item in sorted {
                if let previous = session.last, item.createdAt.timeIntervalSince(previous.createdAt) > maximumGap {
                    emit()
                    session.removeAll(keepingCapacity: true)
                }
                session.append(item)
            }
            emit()
        }
        return output.sorted { $0.endDate > $1.endDate }
    }
}

struct CaptureTimeClusterMonth: Identifiable, Equatable {
    let id: Date
    let month: Date
    let clusters: [CaptureTimeCluster]

    var title: String { month.formatted(.dateTime.year().month(.wide)) }
    var recordCount: Int { clusters.reduce(0) { $0 + $1.items.count } }

    static func months(from items: [CaptureItem]) -> [CaptureTimeClusterMonth] {
        let calendar = Calendar.current
        let clusters = CaptureTimeCluster.clusters(from: items)
        let grouped = Dictionary(grouping: clusters) { cluster in
            let components = calendar.dateComponents([.year, .month], from: cluster.day)
            return calendar.date(from: components) ?? cluster.day
        }
        return grouped.keys.sorted(by: >).map {
            CaptureTimeClusterMonth(id: $0, month: $0, clusters: grouped[$0] ?? [])
        }
    }
}

struct CaptureTimeClusterDay: Identifiable, Equatable {
    let id: Date
    let day: Date
    let clusters: [CaptureTimeCluster]

    var title: String { CaptureTimelineSection.title(for: day) }
    var dateDetail: String { CaptureTimelineSection.dateDetail(for: day) }
    var recordCount: Int { clusters.reduce(0) { $0 + $1.items.count } }

    var timeRange: String {
        let starts = clusters.map(\.startDate)
        let ends = clusters.map(\.endDate)
        guard let start = starts.min(), let end = ends.max() else { return "" }
        return start == end ? start.suijiTime : "\(start.suijiTime) – \(end.suijiTime)"
    }

    static func days(from items: [CaptureItem]) -> [CaptureTimeClusterDay] {
        let clusters = CaptureTimeCluster.clusters(from: items)
        let grouped = Dictionary(grouping: clusters, by: \.day)
        return grouped.keys.sorted(by: >).map { day in
            CaptureTimeClusterDay(
                id: day,
                day: day,
                clusters: (grouped[day] ?? []).sorted { $0.endDate > $1.endDate }
            )
        }
    }
}
