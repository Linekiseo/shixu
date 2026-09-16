import AppKit
import SwiftUI

struct WebArtworkPreview: View {
    let url: URL
    var localArchive: WebArchivePreviewSource? = nil
    @State private var image: NSImage?
    @State private var isLoading = false
    @State private var isLocalArchivePreview = false
    @State private var loadedRequestID: String?
    @State private var subscription: WebPreviewService.Subscription?

    private var domain: String {
        (url.host(percentEncoded: false) ?? "网页")
            .replacingOccurrences(of: "www.", with: "")
    }

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color.blue.opacity(0.2), Color.cyan.opacity(0.07)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            if let image {
                Color.clear
                    .overlay {
                        Image(nsImage: image)
                            .resizable()
                            .scaledToFill()
                    }
                    .clipped()
                LinearGradient(colors: [.clear, .black.opacity(0.34)], startPoint: .center, endPoint: .bottom)
            } else {
                VStack(spacing: 8) {
                    Image(systemName: isLoading ? "arrow.triangle.2.circlepath" : (localArchive == nil ? "globe.asia.australia.fill" : "archivebox.fill"))
                        .font(.system(size: 30, weight: .light))
                    Text(localArchive != nil && isLoading ? "正在读取本机存档" : domain)
                        .font(.caption.weight(.semibold))
                        .lineLimit(1)
                }
                .foregroundStyle(.blue.opacity(0.78))
            }

            HStack(spacing: 5) {
                Circle().fill(.red.opacity(0.76)).frame(width: 6, height: 6)
                Circle().fill(.yellow.opacity(0.82)).frame(width: 6, height: 6)
                Circle().fill(.green.opacity(0.76)).frame(width: 6, height: 6)
                Text(domain)
                    .font(.system(size: 9, weight: .medium, design: .rounded))
                    .foregroundStyle(image == nil ? Color.secondary : Color.white.opacity(0.9))
                    .lineLimit(1)
                Spacer()
            }
            .padding(.horizontal, 10)
            .frame(height: 24)
            .background(image == nil ? AnyShapeStyle(.regularMaterial) : AnyShapeStyle(.black.opacity(0.28)))
            .frame(maxHeight: .infinity, alignment: .top)

            if isLocalArchivePreview {
                Label("本机存档画面", systemImage: "internaldrive.fill")
                    .font(.system(size: 9, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 4)
                    .background(.black.opacity(0.48), in: Capsule())
                    .padding(8)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                    .allowsHitTesting(false)
            }
        }
        .task(id: localArchive?.cacheKey ?? url.absoluteString) {
            // 快速滚动时先让离屏卡片直接取消，避免把短暂出现的链接都加入网络队列。
            try? await Task.sleep(for: .milliseconds(140))
            guard !Task.isCancelled else { return }
            await loadPreview()
        }
        .onDisappear { cancelLoad() }
    }

    @MainActor
    private func loadPreview() async {
        let requestID = localArchive?.cacheKey ?? url.absoluteString
        guard loadedRequestID != requestID else { return }
        cancelLoad()
        loadedRequestID = requestID
        image = nil
        isLoading = true
        isLocalArchivePreview = false

        if let localArchive {
            let localImage = await WebArchiveThumbnailService.shared.image(for: localArchive)
            guard !Task.isCancelled, loadedRequestID == requestID else { return }
            if let localImage {
                image = localImage
                isLoading = false
                isLocalArchivePreview = true
            } else {
                loadOnline(requestID: requestID)
            }
        } else {
            loadOnline(requestID: requestID)
        }
    }

    @MainActor
    private func loadOnline(requestID: String) {
        subscription = WebPreviewService.shared.subscribe(to: url) { result in
            guard loadedRequestID == requestID else { return }
            image = result
            isLoading = false
            isLocalArchivePreview = false
            subscription = nil
        }
    }

    @MainActor
    private func cancelLoad() {
        if let subscription {
            WebPreviewService.shared.unsubscribe(subscription)
        }
        subscription = nil
        loadedRequestID = nil
    }
}
