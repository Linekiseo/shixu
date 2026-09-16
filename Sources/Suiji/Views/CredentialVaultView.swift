import SwiftUI

struct CredentialVaultView: View {
    @ObservedObject var store: CaptureStore
    @State private var isShowingCredentialCapture = false

    private var credentials: [CaptureItem] {
        store.items.filter { !$0.isDeleted && $0.kind == .credential }.sorted { $0.createdAt > $1.createdAt }
    }

    private var sections: [CaptureTimelineSection] {
        CaptureTimelineSection.sections(from: credentials)
    }

    private let columns = [GridItem(.adaptive(minimum: 300, maximum: 430), spacing: 16)]

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()

            if sections.isEmpty {
                LibraryEmptyState(
                    icon: "lock.square",
                    title: "保险箱是空的",
                    description: "账号会按记录日期排列；密码始终只存入 macOS 钥匙串。",
                    actionTitle: "记录账号",
                    actionIcon: "person.badge.plus"
                ) {
                    isShowingCredentialCapture = true
                }
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 22, pinnedViews: [.sectionHeaders]) {
                        ForEach(sections) { section in
                            Section {
                                LazyVGrid(columns: columns, alignment: .leading, spacing: 16) {
                                    ForEach(section.items) { item in
                                        CredentialVaultCard(store: store, item: item)
                                            .overlay {
                                                if store.selectedItemID == item.id {
                                                    RoundedRectangle(cornerRadius: 14)
                                                        .stroke(SuijiTheme.accent, lineWidth: 2)
                                                }
                                            }
                                            .overlay(alignment: .topTrailing) {
                                                CompositionMembershipPill(store: store, item: item)
                                            }
                                            .contentShape(RoundedRectangle(cornerRadius: 14))
                                            .onTapGesture { store.selectedItemID = item.id }
                                    }
                                }
                            } header: {
                                TimelineSectionHeader(section: section, tint: SuijiTheme.accent)
                            }
                        }
                    }
                    .padding(20)
                }
            }
        }
        .navigationSplitViewColumnWidth(min: 500, ideal: 680)
        .sheet(isPresented: $isShowingCredentialCapture) {
            CredentialCaptureSheet(store: store)
        }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text("账号保险箱").font(SuijiTheme.titleFont)
                Text("密码只进入 macOS 钥匙串，正文和搜索索引均不保存明文")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Label("本机已解锁", systemImage: "lock.open.fill")
                .font(.caption)
                .foregroundStyle(.green)
            Button("记录账号", systemImage: "plus") {
                isShowingCredentialCapture = true
            }
            .buttonStyle(.bordered)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 15)
    }
}
