import SwiftUI

struct ContentView: View {
    @ObservedObject var store: CaptureStore
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @State private var inspectorPresented = true
    @State private var inspectorPreference = true

    var body: some View {
        ZStack(alignment: .bottom) {
            NavigationSplitView(columnVisibility: $columnVisibility) {
                SidebarView(store: store)
            } detail: {
                activeLibrary
                    .animation(nil, value: store.destination)
                    .inspector(isPresented: inspectorBinding) {
                        InspectorView(store: store)
                            .inspectorColumnWidth(min: 340, ideal: 420, max: 520)
                    }
                    .toolbar {
                        ToolbarItemGroup(placement: .primaryAction) {
                            if canInspect {
                                Button {
                                    inspectorPreference.toggle()
                                    inspectorPresented = inspectorPreference
                                } label: {
                                    Image(systemName: "sidebar.right")
                                }
                                .help(inspectorPresented ? "隐藏详情" : "显示详情")
                            }

                            Button {
                                SearchPanelController.shared.show()
                            } label: {
                                Image(systemName: "magnifyingglass")
                            }
                            .help("搜索\(AppBrand.displayName)（⌘K）")
                        }
                    }
                }
            .navigationSplitViewStyle(.balanced)

            if let confirmation = store.lastConfirmation {
                Label(confirmation, systemImage: "checkmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(.black.opacity(0.86), in: RoundedRectangle(cornerRadius: 7))
                    .padding(.bottom, 18)
            }
        }
        .frame(minWidth: 1100, minHeight: 720)
        .onAppear { updatePageSelection() }
        .onChange(of: store.destination) { _, _ in updatePageSelection() }
        .onChange(of: store.selectedItemID) { _, _ in updateInspectorVisibility() }
    }

    @ViewBuilder
    private var activeLibrary: some View {
        if store.selectedCollection != nil {
            TimelineBrowseView(store: store)
        } else {
            switch store.category {
            case .inbox:
                InboxView(store: store)
            case .all:
                AllRecordsView(store: store)
            case .favorites, .trash:
                TimelineBrowseView(store: store)
            case .images:
                ImageLibraryView(store: store)
            case .web:
                WebLibraryView(store: store)
            case .credentials:
                CredentialVaultView(store: store)
            case .files:
                DocumentLibraryView(store: store)
            case .compositions:
                CompositionLibraryView(store: store)
            case .monitoring:
                SystemMonitoringView(store: store)
            }
        }
    }

    private var canInspect: Bool {
        store.category != .monitoring && store.selectedItem != nil
    }

    private var inspectorBinding: Binding<Bool> {
        Binding(
            get: { inspectorPresented },
            set: { newValue in
                inspectorPresented = newValue
                if canInspect { inspectorPreference = newValue }
            }
        )
    }

    private func updatePageSelection() {
        if store.category != .monitoring,
           !store.visibleItems.contains(where: { $0.id == store.selectedItemID }) {
            store.selectedItemID = store.visibleItems.first?.id
        }
        updateInspectorVisibility()
    }

    private func updateInspectorVisibility() {
        let shouldPresent = inspectorPreference && canInspect
        guard inspectorPresented != shouldPresent else { return }
        var transaction = Transaction(animation: nil)
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            inspectorPresented = shouldPresent
        }
    }
}
