import SwiftUI

struct CompositionLibraryView: View {
    @ObservedObject var store: CaptureStore

    private var groups: [CaptureCompositionGroup] { store.compositionGroups }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()

            if groups.isEmpty {
                LibraryEmptyState(
                    icon: "square.stack.3d.up",
                    title: "还没有内容组合",
                    description: "把一条记录拖到另一条记录上，相关内容会在这里形成清晰的共同视图。"
                )
            } else {
                ScrollView {
                    LazyVStack(spacing: 20) {
                        ForEach(groups) { group in
                            CompositionTimelineCard(store: store, group: group)
                        }
                    }
                    .padding(22)
                }
            }
        }
        .navigationSplitViewColumnWidth(min: 560, ideal: 760)
    }

    private var header: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 3) {
                Text("内容组合")
                    .font(SuijiTheme.titleFont)
                Text("每个共同容器就是一组；展开后可以直接看清全部成员和顺序")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Label("\(groups.count) 组 · \(groups.reduce(0) { $0 + $1.members.count }) 项", systemImage: "point.3.connected.trianglepath.dotted")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 15)
    }
}
