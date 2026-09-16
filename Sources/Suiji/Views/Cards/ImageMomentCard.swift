import AppKit
import SwiftUI

struct ImageMomentCard: View {
    @ObservedObject var store: CaptureStore
    let item: CaptureItem
    var compactLayout = false

    @ViewBuilder
    var body: some View {
        if compactLayout {
            VStack(spacing: 0) {
                previewArea.frame(height: compactPreviewHeight)
                informationArea
            }
            .frame(maxWidth: .infinity)
            .cardAppearance(tint: .orange)
        } else {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 0) {
                    previewArea.frame(width: 240, height: 154)
                    informationArea.frame(minWidth: 280, maxWidth: .infinity, minHeight: 154, alignment: .topLeading)
                }
                .frame(minWidth: 540)

                VStack(spacing: 0) {
                    previewArea.frame(height: 152)
                    informationArea
                }
            }
            .cardAppearance(tint: .orange)
        }
    }

    private func openPreview() {
        guard let url = store.attachmentURL(for: item) else { return }
        PreviewWindowController.shared.showImage(url: url, title: item.title)
    }

    private var previewArea: some View {
        ZStack {
            artwork
            LinearGradient(colors: [.clear, .black.opacity(0.24)], startPoint: .center, endPoint: .bottom)
            HStack(spacing: 0) {
                Label(item.originalLocation == nil ? "截图" : "本地图片", systemImage: item.originalLocation == nil ? "camera.viewfinder" : "photo")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(.black.opacity(0.4), in: Capsule())
                Spacer()
                Button { openPreview() } label: {
                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                        .foregroundStyle(.white)
                        .frame(width: 28, height: 28)
                        .background(.black.opacity(0.42), in: Circle())
                }
                .buttonStyle(.plain)
                .disabled(store.attachmentURL(for: item) == nil)
                .help("放大预览")
            }
            .padding(10)
            .frame(maxHeight: .infinity, alignment: .top)
        }
    }

    private var informationArea: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(alignment: .top, spacing: 8) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("IMAGE · \(item.fileExtension?.uppercased() ?? "图片")")
                        .font(.system(size: 9, weight: .bold, design: .rounded))
                        .tracking(1.2)
                        .foregroundStyle(.orange)
                    Text(item.title)
                        .font(.custom("Songti SC", size: 17).weight(.semibold))
                        .lineLimit(2)
                }
                Spacer()
                Button { store.toggleFavorite(item.id) } label: {
                    Image(systemName: item.isFavorite ? "star.fill" : "star")
                }
                .buttonStyle(.plain)
                .foregroundStyle(item.isFavorite ? Color.yellow : Color.secondary)
            }

            Text(imageFacts)
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.secondary)
                .lineLimit(1)

            Spacer(minLength: 0)

            HStack(spacing: 8) {
                Label(item.source, systemImage: item.originalLocation == nil ? "viewfinder" : "link")
                    .lineLimit(1)
                Text("·")
                Text(item.createdAt.suijiTime)
                Spacer()
                Button { openPreview() } label: {
                    if compactLayout { Image(systemName: "magnifyingglass") }
                    else { Label("放大", systemImage: "magnifyingglass") }
                }
                    .buttonStyle(.borderless)
                    .font(.caption)
                    .disabled(store.attachmentURL(for: item) == nil)
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
        .padding(14)
    }

    private var imageFacts: String {
        let size = CaptureInsightService.byteCount(item.fileSize)
        guard let url = store.attachmentURL(for: item), let image = NSImage(contentsOf: url) else { return size }
        return "\(Int(image.size.width)) × \(Int(image.size.height))  ·  \(size)"
    }

    @ViewBuilder
    private var artwork: some View {
        if let url = store.attachmentURL(for: item), let image = NSImage(contentsOf: url) {
            Color.clear
                .overlay {
                    Image(nsImage: image)
                        .resizable()
                        .scaledToFill()
                }
                .clipped()
        } else {
            ZStack {
                LinearGradient(colors: [.orange.opacity(0.32), .brown.opacity(0.42)], startPoint: .topLeading, endPoint: .bottomTrailing)
                Image(systemName: "photo.on.rectangle.angled")
                    .font(.system(size: 42, weight: .light))
                    .foregroundStyle(.white.opacity(0.72))
            }
        }
    }

    private var compactPreviewHeight: CGFloat {
        guard let url = store.attachmentURL(for: item), let image = NSImage(contentsOf: url), image.size.height > 0 else { return 178 }
        let ratio = image.size.width / image.size.height
        if ratio < 0.82 { return 262 }
        if ratio < 1.25 { return 228 }
        if ratio < 2.1 { return 198 }
        return 170
    }
}

private extension View {
    func cardAppearance(tint: Color) -> some View {
        self
            .background(Color(nsColor: .controlBackgroundColor).opacity(0.82), in: RoundedRectangle(cornerRadius: 14))
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(tint.opacity(0.2)))
    }
}
