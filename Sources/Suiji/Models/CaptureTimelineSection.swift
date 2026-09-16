import Foundation

protocol TimelineSectionPresenting: Identifiable {
    var title: String { get }
    var dateDetail: String { get }
    var timeRange: String { get }
    var recordCount: Int { get }
}

struct CaptureTimelineSection: Identifiable, TimelineSectionPresenting {
    let id: Date
    let day: Date
    let items: [CaptureItem]

    var recordCount: Int { items.count }

    var title: String { Self.title(for: day) }

    var dateDetail: String { Self.dateDetail(for: day) }

    static func title(for day: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(day) { return "今天" }
        if calendar.isDateInYesterday(day) { return "昨天" }
        if calendar.component(.year, from: day) == calendar.component(.year, from: .now) {
            return day.formatted(.dateTime.month().day())
        }
        return day.formatted(.dateTime.year().month().day())
    }

    static func dateDetail(for day: Date) -> String {
        day.formatted(.dateTime.year().month().day().weekday(.wide))
    }

    var timeRange: String {
        guard let newest = items.first?.createdAt else { return "" }
        guard let oldest = items.last?.createdAt, oldest != newest else { return newest.suijiTime }
        return "\(oldest.suijiTime) – \(newest.suijiTime)"
    }

    static func sections(from items: [CaptureItem]) -> [CaptureTimelineSection] {
        let sorted = items.sorted { $0.createdAt > $1.createdAt }
        let calendar = Calendar.current
        let grouped = Dictionary(grouping: sorted) { calendar.startOfDay(for: $0.createdAt) }

        return grouped.keys.sorted(by: >).map { day in
            CaptureTimelineSection(id: day, day: day, items: grouped[day] ?? [])
        }
    }
}
