import AppKit
import SwiftUI

private enum AllRecordsPresentation: String, CaseIterable, Identifiable {
    case timeline, aggregates
    var id: String { rawValue }
    var title: String { self == .timeline ? "时间线" : "时间片段" }
    var systemImage: String { self == .timeline ? "rectangle.grid.2x2" : "clock.arrow.2.circlepath" }
}

struct AllRecordsView: View {
    @ObservedObject var store: CaptureStore
    @AppStorage("allRecordsPresentation") private var presentationRaw = AllRecordsPresentation.timeline.rawValue
    @State private var query = ""
    @State private var dateScope: SearchDateScope = .all
    @State private var kindScope: SearchKindScope = .all
    @State private var aiPlan: AISearchPlan?
    @State private var aiResultIDs: [CaptureItem.ID]?
    @State private var aiError: String?
    @State private var agentStages: [AgentSearchStage] = []
    @State private var isSearchingWithAI = false
    @FocusState private var searchFocused: Bool

    private var presentation: AllRecordsPresentation {
        get { AllRecordsPresentation(rawValue: presentationRaw) ?? .timeline }
        nonmutating set { presentationRaw = newValue.rawValue }
    }

    private var baseItems: [CaptureItem] {
        if let aiResultIDs {
            let lookup = Dictionary(uniqueKeysWithValues: store.items.map { ($0.id, $0) })
            return aiResultIDs.compactMap { lookup[$0] }.filter { !$0.isDeleted }
        }
        return store.search(query, kind: kindScope, dateScope: dateScope)
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            searchAndFilters
            if !agentStages.isEmpty || aiPlan != nil || aiError != nil {
                Divider()
                agentStatus
            }
            Divider()
            if baseItems.isEmpty { emptyState }
            else if presentation == .timeline {
                CollapsibleTimelineBrowser(store: store, items: baseItems, focusRequest: store.focusRequest)
            } else {
                TimeAggregateBrowser(store: store, items: baseItems)
            }
        }
        .navigationSplitViewColumnWidth(min: 600, ideal: 900)
        .onChange(of: query) { _, _ in clearAIResult() }
        .onChange(of: dateScope) { _, _ in clearAIResult() }
        .onChange(of: kindScope) { _, _ in clearAIResult() }
        .onChange(of: store.focusRequest?.token) { _, _ in prepareForFocusedRecord() }
        .onAppear { if store.focusRequest != nil { prepareForFocusedRecord() } }
    }

    private var header: some View {
        HStack(spacing: 18) {
            VStack(alignment: .leading, spacing: 3) {
                Text("全部记录").font(SuijiTheme.titleFont)
                Text(presentation == .timeline ? "按天折叠，多卡片并行回看" : "像日历一样按年、月、周、日翻阅真实记录")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            metric("今天", store.items.filter { !$0.isDeleted && Calendar.current.isDateInToday($0.createdAt) }.count)
            metric("片段", CaptureTimeCluster.clusters(from: store.items).count)
            metric("总计", store.items.filter { !$0.isDeleted }.count)
            Picker("呈现方式", selection: Binding(get: { presentation }, set: { presentation = $0 })) {
                ForEach(AllRecordsPresentation.allCases) { mode in Label(mode.title, systemImage: mode.systemImage).tag(mode) }
            }
            .pickerStyle(.segmented).labelsHidden().frame(width: 215)
        }
        .padding(.horizontal, 24).padding(.vertical, 14)
    }

    private func metric(_ title: String, _ count: Int) -> some View {
        VStack(alignment: .trailing, spacing: 1) {
            Text("\(count)").font(.headline.monospacedDigit())
            Text(title).font(.system(size: 9)).foregroundStyle(.tertiary)
        }
    }

    private var searchAndFilters: some View {
        HStack(spacing: 9) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("搜索内容、文件、网页、平台、来源 App 或记忆片段…", text: $query)
                    .textFieldStyle(.plain).focused($searchFocused).onSubmit { runAISearch() }
                if !query.isEmpty {
                    Button { query = "" } label: { Image(systemName: "xmark.circle.fill") }
                        .buttonStyle(.plain).foregroundStyle(.tertiary)
                }
            }
            .padding(.horizontal, 11).frame(height: 36)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 9))
            .overlay(RoundedRectangle(cornerRadius: 9).stroke(searchFocused ? Color.accentColor.opacity(0.7) : SuijiTheme.divider))

            Picker("时间", selection: $dateScope) {
                ForEach(SearchDateScope.allCases) { Text($0.title).tag($0) }
            }.pickerStyle(.menu).frame(width: 102)
            Picker("类型", selection: $kindScope) {
                ForEach(SearchKindScope.allCases) { Label($0.title, systemImage: $0.systemImage).tag($0) }
            }.pickerStyle(.menu).frame(width: 106)
            Button {
                runAISearch()
            } label: {
                if isSearchingWithAI { ProgressView().controlSize(.small) }
                else { Label("智能体搜索", systemImage: "sparkles") }
            }
            .buttonStyle(.borderedProminent)
            .disabled(query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSearchingWithAI)
            .help("多智能体理解查询；只把查询文字发给 DeepSeek，记录始终留在本机")
            Text("\(baseItems.count) 条").font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
        }
        .padding(.horizontal, 24).padding(.vertical, 10)
    }

    @ViewBuilder private var agentStatus: some View {
        VStack(alignment: .leading, spacing: 7) {
            if !agentStages.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(agentStages) { stage in
                            Label {
                                Text("\(stage.kind.title) · \(stage.detail)")
                            } icon: {
                                Image(systemName: stage.state == .finished ? "checkmark.circle.fill" : stage.kind.systemImage)
                            }
                            .font(.caption2)
                            .foregroundStyle(stage.state == .finished ? Color.green : (stage.state == .running ? Color.purple : Color.secondary))
                            .padding(.horizontal, 8).padding(.vertical, 5)
                            .background(.quaternary.opacity(0.22), in: Capsule())
                        }
                    }
                }
            }
            HStack(spacing: 8) {
                if let aiPlan {
                    Image(systemName: "sparkles").foregroundStyle(.purple)
                    Text(aiPlan.explanation.isEmpty ? "已在本机完成关系扩展与排序" : aiPlan.explanation).lineLimit(1)
                    Spacer()
                    Text("仅查询文字发送至 DeepSeek · 内容与文档不上传").foregroundStyle(.tertiary)
                    Button("清除") { query = ""; clearAIResult() }.buttonStyle(.borderless)
                } else if let aiError {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                    Text(aiError)
                    Spacer()
                    Button("打开设置") { NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil) }.buttonStyle(.borderless)
                }
            }.font(.caption2)
        }
        .padding(.horizontal, 24).padding(.vertical, 7)
        .background(Color.purple.opacity(0.045))
    }

    private var emptyState: some View {
        LibraryEmptyState(
            icon: query.isEmpty ? "clock" : "magnifyingglass",
            title: query.isEmpty ? "还没有真实记录" : "没有找到相关内容",
            description: query.isEmpty ? "新的文字、截图、网页和文件会自动进入时间线。" : "减少关键词、调整筛选，或让智能体理解自然语言时间与关联内容。",
            actionTitle: query.isEmpty ? "快速记录" : nil,
            actionIcon: "paperclip"
        ) { QuickCapturePanelController.shared.show() }
    }

    private func runAISearch() {
        let clean = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty, !isSearchingWithAI else { return }
        isSearchingWithAI = true
        aiError = nil
        aiPlan = nil
        aiResultIDs = nil
        agentStages = SearchAgentKind.allCases.map { AgentSearchStage(kind: $0, state: .waiting, detail: "等待") }
        Task { @MainActor in
            do {
                let outcome = try await AgentSearchOrchestrator.execute(query: clean, store: store) { agentStages = $0 }
                aiPlan = outcome.plan
                aiResultIDs = outcome.itemIDs
                presentation = .timeline
            } catch {
                aiError = error.localizedDescription
            }
            isSearchingWithAI = false
        }
    }

    private func clearAIResult() {
        aiPlan = nil
        aiResultIDs = nil
        aiError = nil
        agentStages = []
    }

    private func prepareForFocusedRecord() {
        query = ""
        dateScope = .all
        kindScope = .all
        clearAIResult()
        presentation = .timeline
    }
}
