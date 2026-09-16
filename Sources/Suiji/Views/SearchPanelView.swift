import AppKit
import SwiftUI

struct SearchPanelView: View {
    @ObservedObject var store: CaptureStore
    @State private var query = ""
    @State private var dateScope: SearchDateScope = .all
    @State private var kindScope: SearchKindScope = .all
    @State private var aiPlan: AISearchPlan?
    @State private var aiError: String?
    @State private var isSearchingWithAI = false
    @FocusState private var focused: Bool

    private var results: [CaptureItem] {
        aiPlan.map { store.search(query, using: $0) }
            ?? store.search(query, kind: kindScope, dateScope: dateScope)
    }

    private var sections: [CaptureTimelineSection] {
        CaptureTimelineSection.sections(from: Array(results.prefix(60)))
    }

    var body: some View {
        VStack(spacing: 0) {
            searchHeader
            Divider()
            filterBar
            Divider()
            resultTimeline
            Divider()
            footer
        }
        .frame(width: 780, height: 600)
        .background(.thickMaterial)
        .onAppear {
            query = ""
            dateScope = .all
            kindScope = .all
            aiPlan = nil
            aiError = nil
            focused = true
        }
        .onChange(of: query) { _, _ in
            aiPlan = nil
            aiError = nil
        }
        .onExitCommand { SearchPanelController.shared.hide() }
    }

    private var searchHeader: some View {
        HStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .font(.title3)
                .foregroundStyle(.secondary)
            TextField("搜索内容、来源、集合、标签或文件位置…", text: $query)
                .textFieldStyle(.plain)
                .font(.custom("Songti SC", size: 18))
                .focused($focused)
            if !query.isEmpty {
                Button { query = "" } label: { Image(systemName: "xmark.circle.fill") }
                    .buttonStyle(.plain)
                    .foregroundStyle(.tertiary)
            }
            Button {
                runAISearch()
            } label: {
                if isSearchingWithAI {
                    ProgressView().controlSize(.small)
                } else {
                    Label("AI", systemImage: "sparkles")
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSearchingWithAI)
            .help("AI 理解查询后，仍只在本机索引中搜索")
            Text("esc")
                .font(.caption2.monospaced())
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 20)
        .frame(height: 66)
    }

    private var filterBar: some View {
        VStack(spacing: 10) {
            HStack {
                Label(query.isEmpty ? "最近记录" : "搜索结果", systemImage: "clock.arrow.circlepath")
                    .font(.caption.weight(.semibold))
                Text("\(results.count)")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.tertiary)
                Spacer()
                Picker("时间", selection: $dateScope) {
                    ForEach(SearchDateScope.allCases) { scope in Text(scope.title).tag(scope) }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .frame(width: 116)
            }

            HStack(spacing: 6) {
                ForEach(SearchKindScope.allCases) { scope in
                    Button {
                        kindScope = scope
                    } label: {
                        Label(scope.title, systemImage: scope.systemImage)
                            .font(.caption2)
                            .padding(.horizontal, 9)
                            .padding(.vertical, 5)
                            .background(kindScope == scope ? Color.accentColor.opacity(0.16) : Color.clear, in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(kindScope == scope ? .primary : .secondary)
                }
                Spacer()
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 11)
    }

    @ViewBuilder
    private var resultTimeline: some View {
        if results.isEmpty {
            ContentUnavailableView("没有找到", systemImage: "magnifyingglass", description: Text("换一种描述、内容类型或时间范围。"))
                .frame(maxHeight: .infinity)
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 18) {
                    ForEach(sections) { section in
                        VStack(alignment: .leading, spacing: 8) {
                            TimelineSectionHeader(section: section, tint: .accentColor, compact: true)

                            VStack(spacing: 0) {
                                ForEach(Array(section.items.enumerated()), id: \.element.id) { index, item in
                                    SearchTimelineRow(store: store, item: item, isLast: index == section.items.count - 1)
                                }
                            }
                        }
                    }
                }
                .padding(18)
            }
        }
    }

    private var footer: some View {
        HStack {
            if let aiPlan {
                Label(aiPlan.explanation, systemImage: "sparkles")
                    .foregroundStyle(.purple)
                    .lineLimit(1)
            } else if let aiError {
                Label(aiError, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .lineLimit(1)
            } else {
                Text("按时间线回看，不需要记住准确标题")
            }
            Spacer()
            Text("⌘K 随时打开 · AI 不上传资料正文")
        }
        .font(.system(size: 9))
        .foregroundStyle(.tertiary)
        .padding(.horizontal, 18)
        .frame(height: 34)
    }

    private func runAISearch() {
        let clean = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty, !isSearchingWithAI else { return }
        isSearchingWithAI = true
        aiError = nil
        Task {
            do {
                aiPlan = try await DeepSeekAISearchService.interpret(clean)
            } catch {
                aiError = error.localizedDescription
            }
            isSearchingWithAI = false
        }
    }
}

private struct SearchTimelineRow: View {
    @ObservedObject var store: CaptureStore
    let item: CaptureItem
    let isLast: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(spacing: 0) {
                Circle()
                    .fill(item.kind.tint)
                    .frame(width: 9, height: 9)
                    .padding(.top, 19)
                if !isLast {
                    Rectangle()
                        .fill(item.kind.tint.opacity(0.18))
                        .frame(width: 1)
                        .frame(maxHeight: .infinity)
                }
            }
            .frame(width: 14)

            Button {
                SearchPanelController.shared.reveal(item)
            } label: {
                HStack(spacing: 12) {
                    leadingPreview
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 6) {
                            Text(item.kind.cardLabel)
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(item.kind.tint)
                            if let collection = item.collection {
                                Text(collection).font(.caption2).foregroundStyle(.tertiary)
                            }
                            if let kind = item.compositionKind {
                                Label("同组 \(store.compositionMembers(for: item).count)", systemImage: kind.systemImage)
                                    .font(.caption2.weight(.semibold))
                                    .foregroundStyle(kind.tint)
                            }
                        }
                        Text(item.title)
                            .font(.caption.weight(.semibold))
                            .lineLimit(1)
                        Text(detailLine)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    Spacer()
                    Text(item.createdAt.suijiTime)
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.tertiary)
                    Image(systemName: "return")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                .padding(.horizontal, 12)
                .frame(height: 68)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .background(item.kind.tint.opacity(0.045), in: RoundedRectangle(cornerRadius: 9))
            .overlay(RoundedRectangle(cornerRadius: 9).stroke(SuijiTheme.divider))
            .padding(.bottom, isLast ? 0 : 7)
        }
    }

    @ViewBuilder
    private var leadingPreview: some View {
        if item.kind == .image, let url = store.attachmentURL(for: item), let image = NSImage(contentsOf: url) {
            Image(nsImage: image)
                .resizable()
                .scaledToFill()
                .frame(width: 48, height: 48)
                .clipped()
                .clipShape(RoundedRectangle(cornerRadius: 7))
        } else if item.kind == .file || item.textFormat != nil {
            FileTypeIcon(url: store.attachmentURL(for: item), fallbackExtension: item.fileExtension, size: 34)
                .frame(width: 48, height: 48)
                .background(.quaternary.opacity(0.2), in: RoundedRectangle(cornerRadius: 7))
        } else {
            Image(systemName: item.kind.systemImage)
                .font(.title3)
                .foregroundStyle(item.kind.tint)
                .frame(width: 48, height: 48)
                .background(item.kind.tint.opacity(0.09), in: RoundedRectangle(cornerRadius: 7))
        }
    }

    private var detailLine: String {
        switch item.kind {
        case .text: item.textFormat.map { "\($0.title) · .\($0.fileExtension) · \(item.body)" } ?? item.body
        case .image: item.summary
        case .web: item.domain ?? item.body
        case .credential:
            if item.credentialType == .apiKey {
                [item.username, item.apiBaseURL].compactMap { $0 }.joined(separator: " · ")
            } else {
                item.username ?? "账号待补充"
            }
        case .file: [item.fileExtension, item.originalLocation].compactMap { $0 }.joined(separator: " · ")
        }
    }
}
