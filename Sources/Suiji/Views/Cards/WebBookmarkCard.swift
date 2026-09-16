import AppKit
import SwiftUI

struct WebBookmarkCard: View {
    @ObservedObject var store: CaptureStore
    let item: CaptureItem
    var compactLayout = false
    @State private var isShowingOfflineArchive = false

    var body: some View {
        Group {
            if compactLayout {
                VStack(spacing: 0) {
                    preview.frame(height: compactPreviewHeight).clipped()
                    informationArea
                }
                .frame(maxWidth: .infinity)
            } else {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 0) {
                        preview
                            .frame(minWidth: 300, maxWidth: .infinity)
                            .frame(height: 198)
                            .clipped()
                        Rectangle()
                            .fill(Color.blue.opacity(0.14))
                            .frame(width: 1)
                            .padding(.vertical, 14)
                        informationArea.frame(width: 330, height: 198, alignment: .topLeading)
                    }
                    .frame(minWidth: 650)

                    VStack(spacing: 0) {
                        preview.frame(height: 210).clipped()
                        informationArea
                    }
                }
            }
        }
        .webCardAppearance
        .sheet(isPresented: $isShowingOfflineArchive) {
            if let archiveURL = store.webArchiveURL(for: item), let liveURL = URL(string: item.body) {
                OfflineWebArchiveSheet(archiveURL: archiveURL, liveURL: liveURL, item: item)
            }
        }
    }

    @ViewBuilder
    private var preview: some View {
        if let url {
            WebArtworkPreview(url: url, localArchive: item.webArchivePreviewSource)
                .allowsHitTesting(false)
        } else {
            ZStack {
                LinearGradient(colors: [.blue.opacity(0.2), .cyan.opacity(0.08)], startPoint: .topLeading, endPoint: .bottomTrailing)
                Label("链接暂时无法预览", systemImage: "link.badge.plus")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var informationArea: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(alignment: .top, spacing: 10) {
                siteMark
                VStack(alignment: .leading, spacing: 3) {
                    Text("WEB BOOKMARK")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.blue)
                    Text(item.title)
                        .font(.custom("Songti SC", size: 17).weight(.semibold))
                        .lineLimit(2)
                }
                Spacer(minLength: 4)
                Button { store.toggleFavorite(item.id) } label: {
                    Image(systemName: item.isFavorite ? "bookmark.fill" : "bookmark")
                }
                .buttonStyle(.plain)
                .foregroundStyle(item.isFavorite ? .blue : .secondary)
            }

            if !item.summary.isEmpty {
                Text(item.summary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Spacer(minLength: 0)
            HStack(spacing: 7) {
                WebArchiveStatusBadge(item: item)
                Text(item.createdAt.suijiTime)
                Spacer()
                if item.webArchiveState == .archived, store.webArchiveURL(for: item) != nil {
                    Button {
                        isShowingOfflineArchive = true
                    } label: {
                        if compactLayout { Image(systemName: "archivebox.fill") }
                        else { Label("离线快照", systemImage: "archivebox.fill") }
                    }
                    .buttonStyle(.borderless)
                    .foregroundStyle(.green)
                }
                Button {
                    if let url { NSWorkspace.shared.open(url) }
                } label: {
                    if compactLayout { Image(systemName: "arrow.up.right") }
                    else { Label("打开网页", systemImage: "arrow.up.right") }
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.blue)
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
        .padding(13)
    }

    private var siteMark: some View {
        Text(String(domain.prefix(1)).uppercased())
            .font(.headline.weight(.bold))
            .foregroundStyle(.white)
            .frame(width: 36, height: 36)
            .background(Color.blue.gradient, in: RoundedRectangle(cornerRadius: 9))
    }

    private var url: URL? { URL(string: item.body) }

    private var domain: String {
        (item.domain ?? url?.host(percentEncoded: false) ?? "WEB")
            .replacingOccurrences(of: "www.", with: "")
    }

    private var compactPreviewHeight: CGFloat {
        let density = min(42, CGFloat(item.title.count + item.summary.count / 2))
        return 176 + density * 0.9
    }
}

private extension View {
    var webCardAppearance: some View {
        self
            .background(Color(nsColor: .controlBackgroundColor).opacity(0.78), in: RoundedRectangle(cornerRadius: 14))
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.blue.opacity(0.18)))
    }
}
