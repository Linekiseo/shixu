import AppKit
import QuickLookUI
import QuickLookThumbnailing
import SwiftUI
import UniformTypeIdentifiers

struct FileQuickLookPreview: NSViewRepresentable {
    let url: URL

    func makeNSView(context: Context) -> QLPreviewView {
        let view = QLPreviewView(frame: .zero, style: .compact)!
        view.previewItem = url as NSURL
        view.autostarts = true
        return view
    }

    // QLPreviewView 在从窗口移除后会进入不可逆的 deactivated 状态。
    // SwiftUI 仍可能调用 updateNSView，因此这里刻意不重复设置 previewItem；
    // URL 变化由调用方的 .id(url) 创建一张新的预览视图处理。
    func updateNSView(_ nsView: QLPreviewView, context: Context) {}
}

struct FileThumbnailPreview: View {
    let url: URL
    let fallbackExtension: String?
    var immersiveBackdrop = false
    @State private var thumbnail: NSImage?
    @State private var didFail = false

    var body: some View {
        ZStack {
            Color(nsColor: .textBackgroundColor).opacity(0.42)
            if let thumbnail {
                if immersiveBackdrop {
                    Color.clear
                        .overlay {
                            Image(nsImage: thumbnail)
                                .resizable()
                                .scaledToFill()
                                .blur(radius: 18)
                                .opacity(0.3)
                                .scaleEffect(1.08)
                        }
                        .clipped()
                }
                Image(nsImage: thumbnail)
                    .resizable()
                    .scaledToFit()
                    .padding(immersiveBackdrop ? 10 : 6)
                    .shadow(color: .black.opacity(immersiveBackdrop ? 0.22 : 0), radius: 8, y: 3)
            } else if didFail {
                VStack(spacing: 8) {
                    FileTypeIcon(url: url, fallbackExtension: fallbackExtension, size: 52)
                    Text("可在完整预览中打开")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            } else {
                ProgressView()
                    .controlSize(.small)
            }
        }
        .task(id: url) { await loadThumbnail() }
    }

    @MainActor
    private func loadThumbnail() async {
        thumbnail = nil
        didFail = false
        guard FileManager.default.fileExists(atPath: url.path) else {
            didFail = true
            return
        }
        let accessed = url.startAccessingSecurityScopedResource()
        defer { if accessed { url.stopAccessingSecurityScopedResource() } }
        let request = QLThumbnailGenerator.Request(
            fileAt: url,
            size: CGSize(width: 720, height: 480),
            scale: NSScreen.main?.backingScaleFactor ?? 2,
            representationTypes: [.thumbnail, .lowQualityThumbnail, .icon]
        )
        do {
            let representation = try await QLThumbnailGenerator.shared.generateBestRepresentation(for: request)
            guard !Task.isCancelled else { return }
            thumbnail = representation.nsImage
        } catch {
            guard !Task.isCancelled else { return }
            didFail = true
        }
    }
}

struct FileTypeIcon: View {
    let url: URL?
    let fallbackExtension: String?
    var size: CGFloat = 44

    var body: some View {
        Image(nsImage: icon)
            .resizable()
            .scaledToFit()
            .frame(width: size, height: size)
    }

    private var icon: NSImage {
        if let url { return NSWorkspace.shared.icon(forFile: url.path) }
        if let fallbackExtension,
           let type = UTType(filenameExtension: fallbackExtension.lowercased()) {
            return NSWorkspace.shared.icon(for: type)
        }
        return NSImage(systemSymbolName: "doc", accessibilityDescription: "文件") ?? NSImage()
    }
}
