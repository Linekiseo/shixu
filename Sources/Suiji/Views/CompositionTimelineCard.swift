import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct CompositionTimelineCard: View {
    @ObservedObject var store: CaptureStore
    let group: CaptureCompositionGroup
    @State private var isExpanded = true
    @State private var previewOrder: [CaptureItem.ID] = []
    @State private var draggingMemberID: CaptureItem.ID?
    @State private var insertionMemberID: CaptureItem.ID?
    @State private var isDropTarget = false

    private var selectedMember: CaptureItem? {
        group.members.first { $0.id == store.selectedItemID }
    }

    private var displayedMembers: [CaptureItem] {
        guard !previewOrder.isEmpty else { return group.members }
        let lookup = Dictionary(uniqueKeysWithValues: group.members.map { ($0.id, $0) })
        let ordered = previewOrder.compactMap { lookup[$0] }
        return ordered + group.members.filter { !previewOrder.contains($0.id) }
    }

    var body: some View {
        VStack(spacing: 0) {
            groupHeader
            if isExpanded {
                Divider().opacity(0.7)
                memberCards
            } else {
                Divider().opacity(0.7)
                collapsedMembers
            }
        }
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18))
        .overlay(alignment: .leading) {
            Capsule()
                .fill(group.kind.tint.gradient)
                .frame(width: 4)
                .padding(.vertical, 14)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 18)
                .stroke(group.kind.tint.opacity(isDropTarget ? 1 : (selectedMember == nil ? 0.32 : 0.78)), lineWidth: isDropTarget ? 3 : (selectedMember == nil ? 1.5 : 2))
                .allowsHitTesting(false)
        }
        .shadow(color: group.kind.tint.opacity(0.08), radius: 14, y: 5)
        .contentShape(RoundedRectangle(cornerRadius: 18))
        .onDrop(of: [.shixuCaptureRecord], delegate: dropDelegate(before: nil))
        .animation(.snappy(duration: 0.22, extraBounce: 0.08), value: group.members.map(\.id))
        .onAppear { synchronizePreviewOrder() }
        .onChange(of: group.members.map(\.id)) { _, _ in
            guard draggingMemberID == nil else { return }
            synchronizePreviewOrder()
        }
    }

    private var groupHeader: some View {
        HStack(spacing: 13) {
            ZStack {
                RoundedRectangle(cornerRadius: 11)
                    .fill(group.kind.tint.opacity(0.13))
                Image(systemName: group.kind.systemImage)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(group.kind.tint)
            }
            .frame(width: 44, height: 44)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 7) {
                    Text("内容组合")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(group.kind.tint)
                    Text("\(group.members.count) 项")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                    if isDropTarget, draggingMemberID == nil {
                        Label("松开加入组合", systemImage: "plus.circle.fill")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(group.kind.tint)
                    }
                }
                Text(group.title)
                    .font(.custom("Songti SC", size: 18).weight(.semibold))
                    .lineLimit(1)
                Text(group.typeSummary)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if let selectedMember {
                Label("正在查看 \(selectedMember.title)", systemImage: "eye.fill")
                    .font(.caption2)
                    .foregroundStyle(group.kind.tint)
                    .lineLimit(1)
                    .frame(maxWidth: 190)
            }

            Menu {
                Button("在组合资料库查看", systemImage: "square.stack.3d.up.fill") {
                    store.selectCategory(.compositions, selecting: selectedMember?.id ?? group.members.first?.id)
                }
                Divider()
                Button("解除整个组合", systemImage: "rectangle.3.group.bubble.left", role: .destructive) {
                    store.dissolveComposition(group.id)
                }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .menuStyle(.borderlessButton)
            .fixedSize()

            Button {
                withAnimation(.easeInOut(duration: 0.18)) { isExpanded.toggle() }
            } label: {
                Image(systemName: isExpanded ? "chevron.up.circle.fill" : "chevron.down.circle.fill")
                    .font(.title3)
                    .foregroundStyle(group.kind.tint)
            }
            .buttonStyle(.plain)
            .help(isExpanded ? "收起组合" : "展开组合")
        }
        .padding(.leading, 18)
        .padding(.trailing, 14)
        .padding(.vertical, 13)
        .background(
            LinearGradient(
                colors: [group.kind.tint.opacity(0.1), group.kind.tint.opacity(0.025), .clear],
                startPoint: .leading,
                endPoint: .trailing
            )
        )
    }

    private var memberCards: some View {
        Group {
            if displayedMembers.count <= 3 {
                ViewThatFits(in: .horizontal) {
                    flexibleMemberRow
                        .frame(minWidth: memberMinimumFitWidth)
                    scrollingMemberRow
                }
            } else {
                scrollingMemberRow
            }
        }
    }

    private var flexibleMemberRow: some View {
        HStack(alignment: .top, spacing: 10) {
            memberCells(flexibleWidth: true)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .frame(height: memberTileHeight + 28)
        .animation(.snappy(duration: 0.22, extraBounce: 0.08), value: previewOrder)
        .animation(.easeInOut(duration: 0.14), value: insertionMemberID)
    }

    private var scrollingMemberRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .top, spacing: 8) {
                memberCells(flexibleWidth: false)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 14)
            .animation(.snappy(duration: 0.22, extraBounce: 0.08), value: previewOrder)
            .animation(.easeInOut(duration: 0.14), value: insertionMemberID)
        }
        .frame(height: memberTileHeight + 28)
    }

    @ViewBuilder
    private func memberCells(flexibleWidth: Bool) -> some View {
        ForEach(displayedMembers) { member in
            if draggingMemberID != nil, insertionMemberID == member.id {
                insertionMarker
                    .transition(.scale.combined(with: .opacity))
            }
            compositionMemberTile(member, flexibleWidth: flexibleWidth)
                .scaleEffect(draggingMemberID == member.id ? 0.96 : 1)
                .opacity(draggingMemberID == member.id ? 0.62 : 1)
        }
    }

    private func compositionMemberTile(_ member: CaptureItem, flexibleWidth: Bool) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            memberPreview(member)
                .frame(height: 164)
                .clipped()

            memberInformation(member)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .frame(width: flexibleWidth ? nil : 268, height: memberTileHeight, alignment: .top)
        .frame(maxWidth: flexibleWidth ? .infinity : nil, alignment: .top)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.82), in: RoundedRectangle(cornerRadius: 14))
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(
            store.selectedItemID == member.id ? member.kind.tint : SuijiTheme.divider,
            lineWidth: store.selectedItemID == member.id ? 2 : 1
        ))
        .overlay(alignment: .leading) {
            if isDropTarget, draggingMemberID == nil, insertionMemberID == member.id {
                Capsule()
                    .fill(group.kind.tint)
                    .frame(width: 4)
                    .padding(.vertical, 8)
                    .allowsHitTesting(false)
            }
        }
        .overlay(alignment: .topTrailing) {
            Image(systemName: "line.3.horizontal")
                .font(.caption.weight(.bold))
                .foregroundStyle(.white)
                .frame(width: 28, height: 28)
                .background(.black.opacity(0.58), in: Circle())
                .padding(8)
                .allowsHitTesting(false)
                .accessibilityLabel("拖动调整组合顺序")
        }
        .contentShape(RoundedRectangle(cornerRadius: 14))
        .onTapGesture { store.selectedItemID = member.id }
        .onTapGesture(count: 2) { CapturePrimaryAction.perform(store: store, item: member) }
        .onDrag {
            previewOrder = group.members.map(\.id)
            draggingMemberID = member.id
            insertionMemberID = member.id
            return CaptureDragProvider.make(store: store, item: member)
        } preview: {
            HStack(spacing: 9) {
                Image(systemName: member.kind.systemImage)
                    .foregroundStyle(member.kind.tint)
                    .frame(width: 30, height: 30)
                    .background(member.kind.tint.opacity(0.13), in: RoundedRectangle(cornerRadius: 8))
                VStack(alignment: .leading, spacing: 2) {
                    Text(member.title).font(.caption.weight(.semibold)).lineLimit(1)
                    Text("调整组合顺序").font(.system(size: 9)).foregroundStyle(.secondary)
                }
            }
            .padding(10)
            .frame(width: 190, alignment: .leading)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 11))
            .overlay(RoundedRectangle(cornerRadius: 11).stroke(group.kind.tint.opacity(0.6), lineWidth: 1.5))
        }
        .onDrop(of: [.shixuCaptureRecord], delegate: dropDelegate(before: member.id))
        .help("拖入其他卡片可加入组合 · 组内拖动调整顺序 · 双击打开")
    }

    @ViewBuilder
    private func memberPreview(_ member: CaptureItem) -> some View {
        switch member.kind {
        case .image:
            if let url = store.attachmentURL(for: member), let image = NSImage(contentsOf: url) {
                Color.clear
                    .overlay { Image(nsImage: image).resizable().scaledToFill() }
                    .clipped()
            } else {
                previewPlaceholder(icon: "photo", tint: .orange, title: "图片等待连接")
            }
        case .web:
            if let url = URL(string: member.body) {
                WebArtworkPreview(url: url, localArchive: member.webArchivePreviewSource)
                    .allowsHitTesting(false)
            } else {
                previewPlaceholder(icon: "globe", tint: .blue, title: "网页地址不可用")
            }
        case .file:
            if let url = store.attachmentURL(for: member) {
                FileThumbnailPreview(url: url, fallbackExtension: member.fileExtension, immersiveBackdrop: true)
                    .allowsHitTesting(false)
            } else {
                previewPlaceholder(icon: "doc.badge.ellipsis", tint: .teal, title: "文件等待连接")
            }
        case .credential:
            ZStack {
                LinearGradient(colors: [.indigo.opacity(0.22), .purple.opacity(0.055)], startPoint: .topLeading, endPoint: .bottomTrailing)
                VStack(spacing: 9) {
                    CredentialPlatformMark(platform: member.platform, credentialType: member.credentialType ?? .account, size: 54)
                    Text(member.platform ?? (member.credentialType == .apiKey ? "LLM API" : "安全账号"))
                        .font(.headline)
                        .lineLimit(1)
                    Label("macOS 钥匙串", systemImage: "checkmark.shield.fill")
                        .font(.caption2)
                        .foregroundStyle(.green)
                }
            }
        case .text:
            ZStack(alignment: .topLeading) {
                LinearGradient(colors: [.indigo.opacity(0.13), Color(nsColor: .textBackgroundColor).opacity(0.82)], startPoint: .topLeading, endPoint: .bottomTrailing)
                VStack(alignment: .leading, spacing: 7) {
                    Label(member.textFormat?.title ?? "随手文字", systemImage: member.textFormat?.systemImage ?? "text.quote")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.indigo)
                    Text(member.body.isEmpty ? member.title : member.body)
                        .font(member.textFormat == nil ? .custom("Songti SC", size: 12) : .system(size: 9, design: .monospaced))
                        .lineSpacing(3)
                        .lineLimit(7)
                }
                .padding(11)
            }
        }
    }

    private func memberInformation(_ member: CaptureItem) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 6) {
                Label(memberTypeLabel(member), systemImage: member.kind.systemImage)
                    .font(.system(size: 9, weight: .bold, design: .rounded))
                    .tracking(0.7)
                    .foregroundStyle(member.kind.tint)
                    .lineLimit(1)
                Spacer(minLength: 4)
                Button { store.toggleFavorite(member.id) } label: {
                    Image(systemName: member.isFavorite ? "star.fill" : "star")
                }
                .buttonStyle(.plain)
                .foregroundStyle(member.isFavorite ? Color.yellow : Color.secondary)
            }

            Text(member.title)
                .font(.custom("Songti SC", size: 15).weight(.semibold))
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)

            Text(memberDetailLine(member))
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(2)

            Spacer(minLength: 0)

            HStack(spacing: 6) {
                Label(member.sourceApplication ?? member.source, systemImage: member.sourceApplication == nil ? "tray" : "app.badge")
                    .lineLimit(1)
                Text("·")
                Text(member.createdAt.suijiTime).monospacedDigit()
                Spacer(minLength: 3)
                memberQuickAction(member)
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
        .padding(11)
    }

    @ViewBuilder
    private func memberQuickAction(_ member: CaptureItem) -> some View {
        switch member.kind {
        case .image, .file, .text:
            if store.attachmentURL(for: member) != nil {
                Button { CapturePrimaryAction.preview(store: store, item: member) } label: {
                    Image(systemName: "eye")
                }
                .buttonStyle(.borderless)
                .help("预览")
            }
        case .web:
            if let url = URL(string: member.body) {
                Button { NSWorkspace.shared.open(url) } label: {
                    Image(systemName: "arrow.up.right")
                }
                .buttonStyle(.borderless)
                .help("打开网页")
            }
        case .credential:
            if let address = member.apiBaseURL ?? member.loginURL, let url = URL(string: address) {
                Button { NSWorkspace.shared.open(url) } label: {
                    Image(systemName: "arrow.up.right")
                }
                .buttonStyle(.borderless)
                .help("打开绑定地址")
            }
        }
    }

    private func memberTypeLabel(_ member: CaptureItem) -> String {
        switch member.kind {
        case .text: member.textFormat?.title ?? "文字"
        case .image: member.fileExtension?.uppercased() ?? "图片"
        case .web: member.domain ?? "网页"
        case .credential: member.credentialType == .apiKey ? "LLM API" : "账号"
        case .file: member.fileExtension?.uppercased() ?? "文件"
        }
    }

    private func memberDetailLine(_ member: CaptureItem) -> String {
        switch member.kind {
        case .text:
            return "\((member.body.isEmpty ? member.title : member.body).count) 字 · \(member.collection ?? member.source)"
        case .image:
            if let url = store.attachmentURL(for: member), let image = NSImage(contentsOf: url) {
                return "\(Int(image.size.width)) × \(Int(image.size.height)) · \(CaptureInsightService.byteCount(member.fileSize))"
            }
            return CaptureInsightService.byteCount(member.fileSize)
        case .web:
            return "\((member.webArchiveState ?? .queued).title) · \(member.summary.isEmpty ? member.body : member.summary)"
        case .credential:
            let account = member.username ?? "默认凭据"
            let endpoint = member.domain ?? (member.apiBaseURL == nil ? "地址待配置" : "调用地址已配置")
            return "\(account) · \(endpoint)"
        case .file:
            let format = FileFormatDescriptor.describe(url: store.attachmentURL(for: member), fallbackExtension: member.fileExtension)
            let availability = store.attachmentURL(for: member) == nil ? "原文件失联" : "原文件可访问"
            return "\(format.formatName) · \(CaptureInsightService.byteCount(member.fileSize ?? member.backupOriginalSize)) · \(availability)"
        }
    }

    private func previewPlaceholder(icon: String, tint: Color, title: String) -> some View {
        ZStack {
            tint.opacity(0.09)
            VStack(spacing: 8) {
                Image(systemName: icon).font(.system(size: 30, weight: .light))
                Text(title).font(.caption2)
            }
            .foregroundStyle(tint)
        }
    }

    private var insertionMarker: some View {
        VStack(spacing: 5) {
            Text("放在这里")
                .font(.system(size: 9, weight: .bold, design: .rounded))
                .foregroundStyle(group.kind.tint)
                .fixedSize()
                .rotationEffect(.degrees(-90))
                .frame(height: 68)
            Capsule()
                .fill(group.kind.tint.gradient)
                .frame(width: 4, height: 210)
                .shadow(color: group.kind.tint.opacity(0.55), radius: 5)
        }
        .frame(width: 18, height: memberTileHeight)
        .accessibilityLabel("将卡片放在这里")
    }

    private var memberTileHeight: CGFloat { 316 }

    private var memberMinimumFitWidth: CGFloat {
        let count = CGFloat(max(1, displayedMembers.count))
        return count * 228 + max(0, count - 1) * 10 + 36
    }

    private func synchronizePreviewOrder() {
        previewOrder = group.members.map(\.id)
    }

    private func dropDelegate(before destinationID: CaptureItem.ID?) -> CompositionRecordDropDelegate {
        CompositionRecordDropDelegate(
            destinationID: destinationID,
            compositionID: group.id,
            store: store,
            previewOrder: $previewOrder,
            draggingMemberID: $draggingMemberID,
            insertionMemberID: $insertionMemberID,
            isDropTarget: $isDropTarget
        )
    }

    private var collapsedMembers: some View {
        HStack(spacing: 8) {
            ForEach(Array(group.members.prefix(4))) { member in
                Button {
                    store.selectedItemID = member.id
                } label: {
                    HStack(spacing: 7) {
                        Image(systemName: member.compositionDisplayIcon)
                            .foregroundStyle(member.kind.tint)
                        Text(member.title)
                            .lineLimit(1)
                    }
                    .font(.caption)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(member.id == store.selectedItemID ? member.kind.tint.opacity(0.13) : Color.primary.opacity(0.045), in: Capsule())
                }
                .buttonStyle(.plain)
            }
            if group.members.count > 4 {
                Text("+\(group.members.count - 4)")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
    }
}
