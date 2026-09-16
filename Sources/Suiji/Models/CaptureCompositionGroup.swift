import Foundation

struct CaptureCompositionGroup: Identifiable, Equatable {
    let id: UUID
    let kind: CaptureCompositionKind
    let title: String
    let members: [CaptureItem]

    var newestDate: Date {
        members.map(\.createdAt).max() ?? .distantPast
    }

    var oldestDate: Date {
        members.map(\.createdAt).min() ?? .distantPast
    }

    var typeSummary: String {
        let names = members.map(\.kind.title)
        let unique = Array(NSOrderedSet(array: names)).compactMap { $0 as? String }
        return unique.joined(separator: " + ")
    }

    static func groups(from items: [CaptureItem]) -> [CaptureCompositionGroup] {
        let active = items.filter { !$0.isDeleted && $0.compositionID != nil }
        let grouped = Dictionary(grouping: active, by: { $0.compositionID! })
        return grouped.compactMap { id, members in
            guard members.count > 1 else { return nil }
            let ordered = members.sorted {
                let left = $0.compositionOrder ?? Int.max
                let right = $1.compositionOrder ?? Int.max
                if left == right { return $0.createdAt < $1.createdAt }
                return left < right
            }
            let kind = ordered.compactMap(\.compositionKind).first ?? .related
            let title = ordered.compactMap(\.compositionTitle).first ?? "\(kind.title) · \(ordered.count) 项"
            return CaptureCompositionGroup(id: id, kind: kind, title: title, members: ordered)
        }
        .sorted { $0.newestDate > $1.newestDate }
    }
}

struct CaptureTimelineEntry: Identifiable, Equatable {
    enum ID: Hashable {
        case item(UUID)
        case composition(UUID)
    }

    let id: ID
    let item: CaptureItem?
    let group: CaptureCompositionGroup?

    var createdAt: Date {
        group?.newestDate ?? item?.createdAt ?? .distantPast
    }

    var recordCount: Int {
        group?.members.count ?? (item == nil ? 0 : 1)
    }

    static func entries(from items: [CaptureItem]) -> [CaptureTimelineEntry] {
        let sorted = items.sorted { $0.createdAt > $1.createdAt }
        let groups = Dictionary(uniqueKeysWithValues: CaptureCompositionGroup.groups(from: sorted).map { ($0.id, $0) })
        var emittedGroups = Set<UUID>()
        var result: [CaptureTimelineEntry] = []

        for item in sorted {
            if let compositionID = item.compositionID, let group = groups[compositionID] {
                guard emittedGroups.insert(compositionID).inserted else { continue }
                result.append(CaptureTimelineEntry(id: .composition(compositionID), item: nil, group: group))
            } else {
                result.append(CaptureTimelineEntry(id: .item(item.id), item: item, group: nil))
            }
        }
        return result.sorted { $0.createdAt > $1.createdAt }
    }
}

struct CaptureTimelineEntrySection: Identifiable, TimelineSectionPresenting {
    let id: Date
    let day: Date
    let entries: [CaptureTimelineEntry]

    var recordCount: Int { entries.reduce(0) { $0 + $1.recordCount } }

    var title: String { CaptureTimelineSection.title(for: day) }
    var dateDetail: String { CaptureTimelineSection.dateDetail(for: day) }

    var timeRange: String {
        let dates = entries.flatMap { entry -> [Date] in
            if let group = entry.group { return group.members.map(\.createdAt) }
            return entry.item.map { [$0.createdAt] } ?? []
        }.sorted(by: >)
        guard let newest = dates.first else { return "" }
        guard let oldest = dates.last, oldest != newest else { return newest.suijiTime }
        return "\(oldest.suijiTime) – \(newest.suijiTime)"
    }

    static func sections(from items: [CaptureItem]) -> [CaptureTimelineEntrySection] {
        let entries = CaptureTimelineEntry.entries(from: items)
        let calendar = Calendar.current
        let grouped = Dictionary(grouping: entries) { calendar.startOfDay(for: $0.createdAt) }
        return grouped.keys.sorted(by: >).map { day in
            CaptureTimelineEntrySection(id: day, day: day, entries: grouped[day] ?? [])
        }
    }
}
