import SwiftUI

struct CollapsibleTimelineBrowser: View {
    @ObservedObject var store: CaptureStore
    let items: [CaptureItem]
    let focusRequest: CaptureFocusRequest?
    @State private var collapsedDays = Set<Date>()
    @State private var initialized = false

    private var sections: [CaptureTimelineEntrySection] { CaptureTimelineEntrySection.sections(from: items) }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 16, pinnedViews: [.sectionHeaders]) {
                    ForEach(sections) { section in
                        Section {
                            if !collapsedDays.contains(section.day) {
                                LazyVStack(alignment: .leading, spacing: 14) {
                                    let ordinaryItems = section.entries.compactMap(\.item)
                                    let compositionGroups = section.entries.compactMap(\.group)

                                    if !ordinaryItems.isEmpty {
                                        MasonryLayout(minimumColumnWidth: 235, maximumColumns: 6, spacing: 14) {
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

                                    ForEach(compositionGroups) { group in
                                        CompositionTimelineCard(store: store, group: group)
                                            .id(group.id)
                                    }
                                }
                                .padding(.bottom, 8)
                            }
                        } header: {
                            dayHeader(section)
                        }
                    }
                }
                .padding(.horizontal, 22)
                .padding(.vertical, 14)
            }
            .onAppear {
                guard !initialized else { return }
                collapsedDays = Set(sections.dropFirst(2).map(\.day))
                initialized = true
            }
            .onChange(of: focusRequest?.token) { _, _ in
                guard let request = focusRequest,
                      let item = items.first(where: { $0.id == request.itemID }) else { return }
                let day = Calendar.current.startOfDay(for: item.createdAt)
                collapsedDays.remove(day)
                let target: AnyHashable = item.compositionID.map(AnyHashable.init) ?? AnyHashable(item.id)
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(120))
                    withAnimation(.easeInOut) { proxy.scrollTo(target, anchor: .center) }
                }
            }
        }
    }

    private func dayHeader(_ section: CaptureTimelineEntrySection) -> some View {
        Button {
            withAnimation(.snappy) {
                if collapsedDays.contains(section.day) { collapsedDays.remove(section.day) }
                else { collapsedDays.insert(section.day) }
            }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: collapsedDays.contains(section.day) ? "chevron.right.circle.fill" : "chevron.down.circle.fill")
                    .foregroundStyle(SuijiTheme.accent)
                VStack(alignment: .leading, spacing: 1) {
                    Text(section.title).font(.custom("Songti SC", size: 17).weight(.semibold))
                    Text(section.dateDetail).font(.system(size: 9)).foregroundStyle(.tertiary)
                }
                Rectangle().fill(SuijiTheme.divider).frame(height: 1)
                Text(section.timeRange).font(.caption2.monospacedDigit()).foregroundStyle(.tertiary)
                Text("\(section.recordCount) 条").font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
            }
            .padding(.vertical, 7)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(.background.opacity(0.96))
    }
}
