import SwiftUI

struct TimeAggregateBrowser: View {
    @ObservedObject var store: CaptureStore
    let items: [CaptureItem]

    @AppStorage("timeAggregateCalendarLevel") private var level: CaptureCalendarLevel = .month
    @State private var anchorDate = Date.now
    @State private var selectedDay = CaptureCalendarPage.calendar.startOfDay(for: .now)
    @State private var expandedClusters = Set<UUID>()
    @State private var initialized = false

    private let calendar = CaptureCalendarPage.calendar
    private let weekdays = ["一", "二", "三", "四", "五", "六", "日"]

    private var days: [CaptureTimeClusterDay] { CaptureTimeClusterDay.days(from: items) }
    private var dayLookup: [Date: CaptureTimeClusterDay] {
        Dictionary(uniqueKeysWithValues: days.map { ($0.day, $0) })
    }
    private var page: CaptureCalendarPage { CaptureCalendarPage(level: level, anchor: anchorDate) }
    private var pageItems: [CaptureItem] {
        items.filter { !$0.isDeleted && page.interval.contains($0.createdAt) }
    }

    var body: some View {
        VStack(spacing: 0) {
            calendarToolbar
            Divider()

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 16) {
                    calendarSurface

                    if level != .year {
                        selectedDayContent
                    }
                }
                .padding(.horizontal, 22)
                .padding(.vertical, 16)
            }
            .id("\(level.rawValue)-\(page.interval.start.timeIntervalSinceReferenceDate)")
        }
        .onAppear { initializePresentation() }
        .onChange(of: level) { _, _ in alignToCurrentSelection() }
        .onChange(of: items.map(\.id)) { _, _ in reconcilePresentation() }
    }

    private var calendarToolbar: some View {
        HStack(spacing: 12) {
            Picker("日历级别", selection: $level) {
                ForEach(CaptureCalendarLevel.allCases) { option in
                    Text(option.title).tag(option)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 238)

            Divider().frame(height: 26)

            Button { movePage(-1) } label: {
                Image(systemName: "chevron.left")
            }
            .buttonStyle(.borderless)
            .help("上一\(level.title)")

            VStack(alignment: .leading, spacing: 1) {
                Text(page.title)
                    .font(.headline.monospacedDigit())
                Text(page.detail)
                    .font(.system(size: 9))
                    .foregroundStyle(.tertiary)
            }
            .frame(minWidth: 170, alignment: .leading)

            Button { movePage(1) } label: {
                Image(systemName: "chevron.right")
            }
            .buttonStyle(.borderless)
            .help("下一\(level.title)")

            Spacer(minLength: 10)

            Label("\(Set(pageItems.map { calendar.startOfDay(for: $0.createdAt) }).count) 天", systemImage: "calendar.badge.checkmark")
            Text("\(CaptureTimeCluster.clusters(from: pageItems).count) 段")
            Text("\(pageItems.count) 条")
                .fontWeight(.semibold)

            Button { returnToToday() } label: {
                Label("今天", systemImage: "scope")
            }
            .buttonStyle(.bordered)
        }
        .font(.caption)
        .padding(.horizontal, 22)
        .padding(.vertical, 11)
        .background(.bar)
    }

    @ViewBuilder
    private var calendarSurface: some View {
        switch level {
        case .year:
            yearCalendar
        case .month:
            monthCalendar
        case .week:
            weekCalendar
        case .day:
            dayCalendar
        }
    }

    private var yearCalendar: some View {
        VStack(alignment: .leading, spacing: 12) {
            calendarSectionTitle(
                title: "\(calendar.component(.year, from: anchorDate)) 年记录分布",
                detail: "选择月份继续查看；颜色越实，保存内容越多"
            )

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 4), spacing: 10) {
                ForEach(monthsInCurrentYear, id: \.self) { month in
                    monthTile(month)
                }
            }
        }
        .calendarContainer()
    }

    private var monthCalendar: some View {
        VStack(spacing: 8) {
            HStack {
                calendarSectionTitle(
                    title: "月历",
                    detail: "选择一天查看时间片段"
                )
                Spacer()
                if !calendar.isDate(selectedDay, equalTo: anchorDate, toGranularity: .day) {
                    Text(selectedDay.suijiDayLabel)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            LazyVGrid(columns: sevenColumns, spacing: 6) {
                ForEach(weekdays, id: \.self) { weekday in
                    Text(weekday)
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.tertiary)
                        .frame(maxWidth: .infinity)
                }

                ForEach(page.monthGridDays, id: \.self) { date in
                    monthDayCell(date)
                }
            }
        }
        .calendarContainer()
    }

    private var weekCalendar: some View {
        VStack(alignment: .leading, spacing: 10) {
            calendarSectionTitle(title: "本周", detail: "比较每天的记录密度，选择一天查看")

            LazyVGrid(columns: sevenColumns, spacing: 8) {
                ForEach(Array(page.days.enumerated()), id: \.element) { index, date in
                    weekDayCell(date, weekday: weekdays[index % weekdays.count])
                }
            }
        }
        .calendarContainer()
    }

    private var dayCalendar: some View {
        VStack(alignment: .leading, spacing: 12) {
            calendarSectionTitle(title: "当天活动", detail: "24 小时记录密度")

            HStack(alignment: .bottom, spacing: 4) {
                ForEach(0..<24, id: \.self) { hour in
                    VStack(spacing: 4) {
                        RoundedRectangle(cornerRadius: 2.5)
                            .fill(hourCount(hour) == 0 ? Color.secondary.opacity(0.1) : SuijiTheme.accent.opacity(hourOpacity(hour)))
                            .frame(height: hourBarHeight(hour))
                        Text(hour % 6 == 0 ? String(format: "%02d", hour) : "")
                            .font(.system(size: 8).monospacedDigit())
                            .foregroundStyle(.tertiary)
                            .frame(height: 9)
                    }
                    .frame(maxWidth: .infinity, alignment: .bottom)
                }
            }
            .frame(height: 66, alignment: .bottom)
        }
        .calendarContainer()
    }

    private var selectedDayContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(CaptureTimelineSection.title(for: selectedDay))
                        .font(.custom("Songti SC", size: 19).weight(.semibold))
                    Text(CaptureTimelineSection.dateDetail(for: selectedDay))
                        .font(.system(size: 9))
                        .foregroundStyle(.tertiary)
                }

                Rectangle().fill(SuijiTheme.divider).frame(height: 1)

                if let day = dayLookup[selectedDay] {
                    Text(day.timeRange)
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.tertiary)
                    Text("\(day.clusters.count) 段 · \(day.recordCount) 条")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                } else {
                    Text("没有记录")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }

                if level != .day {
                    Button {
                        withAnimation(.snappy) { level = .day }
                    } label: {
                        Label("进入日视图", systemImage: "arrow.right")
                    }
                    .buttonStyle(.borderless)
                    .font(.caption2)
                }
            }

            if let day = dayLookup[selectedDay] {
                LazyVStack(alignment: .leading, spacing: 12) {
                    ForEach(day.clusters) { cluster in
                        clusterPanel(cluster)
                    }
                }
            } else {
                noRecordsForSelectedDay
            }
        }
    }

    private func calendarSectionTitle(title: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.subheadline.weight(.semibold))
            Text(detail)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    private var monthsInCurrentYear: [Date] {
        let year = calendar.component(.year, from: anchorDate)
        return (1...12).compactMap { month in
            calendar.date(from: DateComponents(year: year, month: month, day: 1))
        }
    }

    private func monthTile(_ month: Date) -> some View {
        let monthPage = CaptureCalendarPage(level: .month, anchor: month)
        let monthItems = items.filter { !$0.isDeleted && monthPage.interval.contains($0.createdAt) }
        let counts = recordCountsByDay(monthItems)
        let monthNumber = calendar.component(.month, from: month)

        return Button {
            withAnimation(.snappy) {
                anchorDate = month
                level = .month
                selectBestDay(in: monthPage.interval, fallback: month)
            }
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("\(monthNumber)月")
                        .font(.headline.monospacedDigit())
                    Spacer()
                    Text(monthItems.isEmpty ? "无记录" : "\(monthItems.count) 条")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(monthItems.isEmpty ? .tertiary : .secondary)
                }

                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 3), count: 7), spacing: 3) {
                    ForEach(monthPage.monthGridDays, id: \.self) { date in
                        let count = counts[calendar.startOfDay(for: date), default: 0]
                        RoundedRectangle(cornerRadius: 1.5)
                            .fill(miniDayColor(count: count, belongsToMonth: calendar.isDate(date, equalTo: month, toGranularity: .month)))
                            .frame(height: 5)
                    }
                }
            }
            .padding(11)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(Color.primary.opacity(monthItems.isEmpty ? 0.018 : 0.035), in: RoundedRectangle(cornerRadius: 11))
        .overlay {
            RoundedRectangle(cornerRadius: 11)
                .stroke(monthItems.isEmpty ? SuijiTheme.divider : SuijiTheme.accent.opacity(0.2))
        }
    }

    private func monthDayCell(_ date: Date) -> some View {
        let day = calendar.startOfDay(for: date)
        let count = dayLookup[day]?.recordCount ?? 0
        let isSelected = calendar.isDate(day, inSameDayAs: selectedDay)
        let belongsToMonth = calendar.isDate(date, equalTo: anchorDate, toGranularity: .month)
        let isToday = calendar.isDateInToday(day)

        return Button {
            select(day)
        } label: {
            VStack(alignment: .leading, spacing: 5) {
                HStack {
                    Text("\(calendar.component(.day, from: date))")
                        .font(.caption.monospacedDigit().weight(isSelected || isToday ? .bold : .regular))
                    Spacer()
                    if count > 0 {
                        Text("\(count)")
                            .font(.system(size: 9).monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }
                HStack(spacing: 3) {
                    ForEach(activityKinds(on: day).prefix(4), id: \.self) { kind in
                        Circle().fill(kind.tint).frame(width: 5, height: 5)
                    }
                    Spacer(minLength: 0)
                }
            }
            .padding(8)
            .frame(maxWidth: .infinity, minHeight: 49, alignment: .topLeading)
            .opacity(belongsToMonth ? 1 : 0.34)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(dayCellBackground(isSelected: isSelected, count: count), in: RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(isToday ? SuijiTheme.accent.opacity(0.8) : (isSelected ? SuijiTheme.accent.opacity(0.45) : SuijiTheme.divider), lineWidth: isToday ? 1.5 : 1)
        }
    }

    private func weekDayCell(_ date: Date, weekday: String) -> some View {
        let day = calendar.startOfDay(for: date)
        let count = dayLookup[day]?.recordCount ?? 0
        let isSelected = calendar.isDate(day, inSameDayAs: selectedDay)
        let isToday = calendar.isDateInToday(day)

        return Button { select(day) } label: {
            VStack(spacing: 6) {
                Text("周\(weekday)")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.secondary)
                Text("\(calendar.component(.day, from: date))")
                    .font(.title3.monospacedDigit().weight(isSelected || isToday ? .bold : .regular))
                HStack(spacing: 3) {
                    ForEach(activityKinds(on: day).prefix(4), id: \.self) { kind in
                        Circle().fill(kind.tint).frame(width: 5, height: 5)
                    }
                }
                .frame(height: 5)
                Text(count == 0 ? "—" : "\(count) 条")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(count == 0 ? .tertiary : .secondary)
            }
            .frame(maxWidth: .infinity, minHeight: 92)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(dayCellBackground(isSelected: isSelected, count: count), in: RoundedRectangle(cornerRadius: 10))
        .overlay {
            RoundedRectangle(cornerRadius: 10)
                .stroke(isToday ? SuijiTheme.accent.opacity(0.8) : (isSelected ? SuijiTheme.accent.opacity(0.45) : SuijiTheme.divider), lineWidth: isToday ? 1.5 : 1)
        }
    }

    private func clusterPanel(_ cluster: CaptureTimeCluster) -> some View {
        let expanded = expandedClusters.contains(cluster.id)
        let tint = dominantTint(for: cluster)

        return VStack(spacing: 0) {
            Button {
                withAnimation(.snappy(duration: 0.24, extraBounce: 0.05)) {
                    if expanded { expandedClusters.remove(cluster.id) }
                    else { expandedClusters.insert(cluster.id) }
                }
            } label: {
                clusterHeader(cluster, expanded: expanded, tint: tint)
            }
            .buttonStyle(.plain)

            if expanded {
                Divider().opacity(0.68)
                expandedContent(cluster)
                    .padding(14)
            } else {
                Divider().opacity(0.48)
                collapsedPreview(cluster)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 9)
            }
        }
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
        .overlay(alignment: .leading) {
            Capsule()
                .fill(tint.gradient)
                .frame(width: 4)
                .padding(.vertical, 12)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 16)
                .stroke(tint.opacity(expanded ? 0.38 : 0.19), lineWidth: expanded ? 1.5 : 1)
        }
    }

    private func clusterHeader(_ cluster: CaptureTimeCluster, expanded: Bool, tint: Color) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(cluster.timeRange)
                    .font(.headline.monospacedDigit())
                Text("\(cluster.items.count) 条")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            .frame(minWidth: 108, alignment: .leading)

            Rectangle().fill(tint.opacity(0.2)).frame(width: 1, height: 32)

            HStack(spacing: 7) {
                if !sourceNames(for: cluster).isEmpty {
                    ForEach(sourceNames(for: cluster), id: \.self) { source in
                        Label(source, systemImage: "app.badge")
                            .lineLimit(1)
                    }
                } else {
                    Label("本机记录", systemImage: "tray.full")
                }
            }
            .font(.caption2.weight(.medium))
            .foregroundStyle(.secondary)

            Spacer(minLength: 8)

            HStack(spacing: 8) {
                ForEach(kindCounts(for: cluster).prefix(4), id: \.kind) { entry in
                    Label("\(entry.count)", systemImage: entry.kind.systemImage)
                        .foregroundStyle(entry.kind.tint)
                }
            }
            .font(.caption2.monospacedDigit())

            Image(systemName: expanded ? "chevron.up.circle.fill" : "chevron.down.circle.fill")
                .font(.title3)
                .foregroundStyle(tint)
        }
        .padding(.leading, 18)
        .padding(.trailing, 14)
        .padding(.vertical, 11)
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private func expandedContent(_ cluster: CaptureTimeCluster) -> some View {
        let entries = CaptureTimelineEntry.entries(from: cluster.items)
        let ordinaryItems = entries.compactMap(\.item)
        let groups = entries.compactMap(\.group)

        LazyVStack(alignment: .leading, spacing: 14) {
            if !ordinaryItems.isEmpty {
                MasonryLayout(minimumColumnWidth: 235, maximumColumns: 6, spacing: 12) {
                    ForEach(ordinaryItems) { item in
                        CaptureRow(
                            store: store,
                            item: item,
                            selected: store.selectedItemID == item.id,
                            compactLayout: true
                        )
                        .id(item.id)
                    }
                }
            }

            ForEach(groups) { group in
                CompositionTimelineCard(store: store, group: group)
                    .id(group.id)
            }
        }
    }

    private func collapsedPreview(_ cluster: CaptureTimeCluster) -> some View {
        HStack(spacing: 8) {
            ForEach(cluster.items.prefix(2)) { item in
                HStack(spacing: 6) {
                    Image(systemName: item.kind.systemImage)
                        .foregroundStyle(item.kind.tint)
                    Text(item.title)
                        .lineLimit(1)
                }
                .font(.caption2)
                .padding(.horizontal, 9)
                .padding(.vertical, 5)
                .background(item.kind.tint.opacity(0.075), in: Capsule())
            }
            if cluster.items.count > 2 {
                Text("+\(cluster.items.count - 2)")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
    }

    private var noRecordsForSelectedDay: some View {
        HStack(spacing: 12) {
            Image(systemName: "calendar.badge.minus")
                .font(.title2)
                .foregroundStyle(.tertiary)
            VStack(alignment: .leading, spacing: 2) {
                Text("这一天没有记录")
                    .font(.subheadline.weight(.medium))
                Text("可选择日历中带有彩色标记的日期，或继续翻页。")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(18)
        .background(Color.primary.opacity(0.025), in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(SuijiTheme.divider))
    }

    private var sevenColumns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: 6), count: 7)
    }

    private func recordCountsByDay(_ sourceItems: [CaptureItem]) -> [Date: Int] {
        Dictionary(grouping: sourceItems) { calendar.startOfDay(for: $0.createdAt) }
            .mapValues(\.count)
    }

    private func activityKinds(on day: Date) -> [CaptureKind] {
        guard let day = dayLookup[calendar.startOfDay(for: day)] else { return [] }
        return Dictionary(grouping: day.clusters.flatMap(\.items), by: \.kind)
            .sorted {
                if $0.value.count == $1.value.count { return $0.key.rawValue < $1.key.rawValue }
                return $0.value.count > $1.value.count
            }
            .map(\.key)
    }

    private func miniDayColor(count: Int, belongsToMonth: Bool) -> Color {
        guard belongsToMonth else { return Color.clear }
        guard count > 0 else { return Color.secondary.opacity(0.09) }
        return SuijiTheme.accent.opacity(min(0.9, 0.28 + Double(count) * 0.1))
    }

    private func dayCellBackground(isSelected: Bool, count: Int) -> Color {
        if isSelected { return SuijiTheme.accent.opacity(0.12) }
        if count > 0 { return Color.primary.opacity(0.045) }
        return Color.primary.opacity(0.015)
    }

    private func hourCount(_ hour: Int) -> Int {
        guard let day = dayLookup[selectedDay] else { return 0 }
        return day.clusters.flatMap(\.items).filter { calendar.component(.hour, from: $0.createdAt) == hour }.count
    }

    private func hourBarHeight(_ hour: Int) -> CGFloat {
        let maximum = max(1, (0..<24).map(hourCount).max() ?? 1)
        let ratio = CGFloat(hourCount(hour)) / CGFloat(maximum)
        return max(4, 8 + ratio * 35)
    }

    private func hourOpacity(_ hour: Int) -> Double {
        let maximum = max(1, (0..<24).map(hourCount).max() ?? 1)
        return 0.28 + (Double(hourCount(hour)) / Double(maximum)) * 0.62
    }

    private func sourceNames(for cluster: CaptureTimeCluster) -> [String] {
        let values = cluster.items.compactMap { item in
            item.sourceApplication ?? (item.source.isEmpty ? nil : item.source)
        }
        let counts = Dictionary(grouping: values, by: { $0 }).mapValues(\.count)
        return counts.sorted {
            if $0.value == $1.value { return $0.key < $1.key }
            return $0.value > $1.value
        }
        .prefix(2)
        .map(\.key)
    }

    private func kindCounts(for cluster: CaptureTimeCluster) -> [(kind: CaptureKind, count: Int)] {
        Dictionary(grouping: cluster.items, by: \.kind)
            .map { (kind: $0.key, count: $0.value.count) }
            .sorted {
                if $0.count == $1.count { return $0.kind.rawValue < $1.kind.rawValue }
                return $0.count > $1.count
            }
    }

    private func dominantTint(for cluster: CaptureTimeCluster) -> Color {
        kindCounts(for: cluster).first?.kind.tint ?? SuijiTheme.accent
    }

    private func select(_ day: Date) {
        let normalized = calendar.startOfDay(for: day)
        withAnimation(.snappy(duration: 0.2)) {
            selectedDay = normalized
            anchorDate = normalized
            expandFirstCluster(on: normalized)
        }
    }

    private func movePage(_ direction: Int) {
        let nextAnchor = page.shifted(by: direction)
        let nextPage = CaptureCalendarPage(level: level, anchor: nextAnchor)
        withAnimation(.snappy(duration: 0.22)) {
            anchorDate = nextAnchor
            if level != .year {
                selectBestDay(in: nextPage.interval, fallback: nextAnchor)
            }
        }
    }

    private func returnToToday() {
        let today = calendar.startOfDay(for: .now)
        withAnimation(.snappy(duration: 0.22)) {
            anchorDate = today
            selectedDay = today
            expandFirstCluster(on: today)
        }
    }

    private func selectBestDay(in interval: DateInterval, fallback: Date) {
        let candidate = days.first(where: { interval.contains($0.day) })?.day
            ?? calendar.startOfDay(for: fallback)
        selectedDay = candidate
        anchorDate = level == .year ? fallback : candidate
        expandFirstCluster(on: candidate)
    }

    private func expandFirstCluster(on day: Date) {
        if let first = dayLookup[calendar.startOfDay(for: day)]?.clusters.first {
            expandedClusters.insert(first.id)
        }
    }

    private func initializePresentation() {
        guard !initialized else { return }
        let latestDay = days.first?.day ?? calendar.startOfDay(for: .now)
        anchorDate = latestDay
        selectedDay = latestDay
        expandFirstCluster(on: latestDay)
        initialized = true
    }

    private func alignToCurrentSelection() {
        anchorDate = selectedDay
        if level != .year { expandFirstCluster(on: selectedDay) }
    }

    private func reconcilePresentation() {
        let validClusters = Set(days.flatMap(\.clusters).map(\.id))
        expandedClusters.formIntersection(validClusters)

        guard let latest = days.first?.day else { return }
        if !page.interval.contains(latest), dayLookup[selectedDay] == nil {
            anchorDate = latest
            selectedDay = latest
        }
        expandFirstCluster(on: selectedDay)
    }
}

private extension View {
    func calendarContainer() -> some View {
        padding(14)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(SuijiTheme.divider))
    }
}
