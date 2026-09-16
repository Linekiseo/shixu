import SwiftUI

extension CaptureCompositionKind {
    var tint: Color {
        switch self {
        case .llmAPI: .indigo
        case .videoGroup: .purple
        case .related: .mint
        }
    }

    var overviewTitle: String {
        switch self {
        case .llmAPI: "API 配置组合"
        case .videoGroup: "视频素材组合"
        case .related: "关联内容组合"
        }
    }
}

extension CaptureItem {
    var compositionDisplayIcon: String {
        if credentialType == .apiKey { return "key.horizontal.fill" }
        if compositionKind == .videoGroup { return "play.rectangle" }
        return kind.systemImage
    }

    var compositionDisplayRole: String {
        if credentialType == .apiKey { return "API 密钥 · 钥匙串保护" }
        if kind == .web { return domain ?? "网页地址" }
        if compositionKind == .videoGroup { return fileExtension ?? "视频素材" }
        if let textFormat { return "\(textFormat.title) · .\(textFormat.fileExtension)" }
        return kind.title
    }
}

struct CompositionMembershipPill: View {
    @ObservedObject var store: CaptureStore
    let item: CaptureItem

    var body: some View {
        if let kind = item.compositionKind {
            Label("同组 \(store.compositionMembers(for: item).count) 项", systemImage: kind.systemImage)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(kind.tint)
                .padding(.horizontal, 9)
                .padding(.vertical, 6)
                .background(.thickMaterial, in: Capsule())
                .overlay(Capsule().stroke(kind.tint.opacity(0.35)))
                .shadow(color: .black.opacity(0.08), radius: 5, y: 2)
                .padding(9)
                .allowsHitTesting(false)
        }
    }
}
