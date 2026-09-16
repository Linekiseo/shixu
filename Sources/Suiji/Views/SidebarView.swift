import SwiftUI

struct SidebarView: View {
    @ObservedObject var store: CaptureStore

    private let capture: [SidebarCategory] = [.inbox, .all]
    private let library: [SidebarCategory] = [.images, .web, .credentials, .files, .compositions, .favorites]

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 2) {
                Text(AppBrand.displayName)
                    .font(.custom("Songti SC", size: 24).weight(.bold))
                Text(".")
                    .font(.title2.weight(.bold))
                    .foregroundStyle(SuijiTheme.accent)
                Spacer()
            }
            .padding(.horizontal, 14)
            .padding(.top, 16)
            .padding(.bottom, 18)

            List(selection: categorySelection) {
                Section("收集") {
                    ForEach(capture) { category in
                        Label(category.title, systemImage: category.systemImage)
                            .tag(category)
                    }
                }

                Section("资料库") {
                    ForEach(library) { category in
                        Label(category.title, systemImage: category.systemImage)
                            .tag(category)
                    }
                }

                if !store.availableCollections.isEmpty {
                    Section("自动整理") {
                        ForEach(store.availableCollections, id: \.self) { collection in
                            Button {
                                store.selectCollection(collection)
                            } label: {
                                HStack(spacing: 9) {
                                    Image(systemName: "square.stack.3d.up")
                                        .foregroundStyle(store.selectedCollection == collection ? SuijiTheme.accent : .secondary)
                                        .frame(width: 16)
                                    Text(collection)
                                    Spacer()
                                    Text("\(store.count(in: collection))")
                                        .font(.caption2.monospacedDigit())
                                        .foregroundStyle(.tertiary)
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .listRowBackground(store.selectedCollection == collection ? SuijiTheme.accent.opacity(0.13) : Color.clear)
                        }
                    }
                }

                Section("自动化") {
                    HStack {
                        Label(SidebarCategory.monitoring.title, systemImage: SidebarCategory.monitoring.systemImage)
                        Spacer()
                        let pending = store.systemSignals.filter { $0.state == .pending }.count
                        if pending > 0 {
                            Text("\(pending)")
                                .font(.caption2)
                                .padding(.horizontal, 5)
                                .background(SuijiTheme.accent.opacity(0.15), in: Capsule())
                        }
                    }
                    .tag(SidebarCategory.monitoring)
                }

                Section {
                    Label(SidebarCategory.trash.title, systemImage: SidebarCategory.trash.systemImage)
                        .tag(SidebarCategory.trash)
                }
            }
            .listStyle(.sidebar)

            Button {
                QuickCapturePanelController.shared.show()
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "paperclip")
                        .frame(width: 28, height: 28)
                        .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))
                    VStack(alignment: .leading, spacing: 1) {
                        Text("快速记录").font(.caption.weight(.semibold))
                        Text("⌘ ⇧ Space").font(.caption2).foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(12)
        }
        .navigationSplitViewColumnWidth(min: 180, ideal: 208, max: 240)
    }

    private var categorySelection: Binding<SidebarCategory?> {
        Binding(
            get: { store.selectedCollection == nil ? store.category : nil },
            set: { newValue in
                guard let newValue, newValue != store.category || store.selectedCollection != nil else { return }
                Task { @MainActor in
                    await Task.yield()
                    store.selectCategory(newValue)
                }
            }
        )
    }
}
