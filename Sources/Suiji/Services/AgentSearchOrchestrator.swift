import Foundation

enum SearchAgentKind: String, CaseIterable, Identifiable, Sendable {
    case intent, temporal, retrieval, relations, ranking
    var id: String { rawValue }
    var title: String {
        switch self {
        case .intent: "理解意图"
        case .temporal: "解析时间"
        case .retrieval: "本地召回"
        case .relations: "扩展关联"
        case .ranking: "综合排序"
        }
    }
    var systemImage: String {
        switch self {
        case .intent: "quote.bubble"
        case .temporal: "calendar.badge.clock"
        case .retrieval: "externaldrive.badge.magnifyingglass"
        case .relations: "point.3.connected.trianglepath.dotted"
        case .ranking: "line.3.horizontal.decrease"
        }
    }
}

struct AgentSearchStage: Identifiable, Equatable, Sendable {
    enum State: Equatable, Sendable { case waiting, running, finished }
    var id: SearchAgentKind { kind }
    let kind: SearchAgentKind
    var state: State
    var detail: String
}

struct AgentSearchOutcome: Sendable {
    let plan: AISearchPlan
    let itemIDs: [CaptureItem.ID]
}

@MainActor
enum AgentSearchOrchestrator {
    static func execute(
        query: String,
        store: CaptureStore,
        onStage: @escaping ([AgentSearchStage]) -> Void
    ) async throws -> AgentSearchOutcome {
        var stages = SearchAgentKind.allCases.map { AgentSearchStage(kind: $0, state: .waiting, detail: "等待") }
        func update(_ kind: SearchAgentKind, _ state: AgentSearchStage.State, _ detail: String) {
            guard let index = stages.firstIndex(where: { $0.kind == kind }) else { return }
            stages[index].state = state
            stages[index].detail = detail
            onStage(stages)
        }

        update(.intent, .running, "只发送查询文字")
        let plan = try await DeepSeekAISearchService.interpret(query)
        update(.intent, .finished, "已提取关键词与类型")

        update(.temporal, .running, "校准自然语言日期")
        let hasDate = plan.startDate != nil || plan.endDate != nil || plan.fallbackDateScope != .all
        update(.temporal, .finished, hasDate ? "已应用时间边界" : "不限时间")

        update(.retrieval, .running, "扫描本机索引")
        let base = store.search(query, using: plan)
        update(.retrieval, .finished, "召回 \(base.count) 条")

        update(.relations, .running, "检查组合与相似记录")
        let expanded = expandRelations(base, plan: plan, store: store)
        update(.relations, .finished, "补充 \(max(0, expanded.count - base.count)) 条关联")

        update(.ranking, .running, "去重并整理顺序")
        let ranked = rank(expanded, preferred: base)
        update(.ranking, .finished, "得到 \(ranked.count) 条结果")
        return AgentSearchOutcome(plan: plan, itemIDs: ranked.map(\.id))
    }

    static func expandRelations(_ base: [CaptureItem], plan: AISearchPlan, store: CaptureStore) -> [CaptureItem] {
        var result = base
        var seen = Set(base.map(\.id))
        for item in base.prefix(20) {
            let candidates = store.compositionMembers(for: item) + store.relatedItems(to: item, limit: 2)
            for candidate in candidates where candidateMatchesScope(candidate, plan: plan) {
                if seen.insert(candidate.id).inserted { result.append(candidate) }
            }
        }
        return result
    }

    static func rank(_ items: [CaptureItem], preferred: [CaptureItem]) -> [CaptureItem] {
        let preferredRank = Dictionary(uniqueKeysWithValues: preferred.enumerated().map { ($0.element.id, $0.offset) })
        return Dictionary(uniqueKeysWithValues: items.map { ($0.id, $0) }).values.sorted { left, right in
            switch (preferredRank[left.id], preferredRank[right.id]) {
            case let (l?, r?): l < r
            case (_?, nil): true
            case (nil, _?): false
            case (nil, nil): left.createdAt > right.createdAt
            }
        }
    }

    private static func candidateMatchesScope(_ item: CaptureItem, plan: AISearchPlan) -> Bool {
        guard plan.kindScope.includes(item) else { return false }
        if let start = plan.boundaryDate(plan.startDate, endOfDay: false), item.createdAt < start { return false }
        if let end = plan.boundaryDate(plan.endDate, endOfDay: true), item.createdAt >= end { return false }
        if let collection = plan.collection, !collection.isEmpty, item.collection != collection { return false }
        return true
    }
}
