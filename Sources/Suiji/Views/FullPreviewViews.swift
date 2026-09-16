import AppKit
import SwiftUI

struct ImagePreviewSheet: View {
    @Environment(\.dismiss) private var dismiss
    let url: URL
    let title: String
    var onClose: (() -> Void)? = nil

    @State private var zoom: CGFloat = 1
    @State private var fitRequest = 0

    private var image: NSImage? { NSImage(contentsOf: url) }

    var body: some View {
        VStack(spacing: 0) {
            previewHeader
            Divider()

            if let image {
                ZoomableImageCanvas(image: image, zoom: $zoom, fitRequest: fitRequest)
            } else {
                ContentUnavailableView("图片暂时不可用", systemImage: "photo.badge.exclamationmark", description: Text(url.path))
            }
        }
        .frame(minWidth: 760, minHeight: 560)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var previewHeader: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline).lineLimit(1)
                if let image {
                    Text("\(Int(image.size.width)) × \(Int(image.size.height)) · \(url.pathExtension.uppercased())")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()

            HStack(spacing: 4) {
                Button { zoom = max(0.1, zoom / 1.2) } label: { Image(systemName: "minus.magnifyingglass") }
                    .help("缩小")
                Text("\(Int(zoom * 100))%")
                    .font(.caption.monospacedDigit())
                    .frame(width: 50)
                Button { zoom = min(8, zoom * 1.2) } label: { Image(systemName: "plus.magnifyingglass") }
                    .help("放大")
                Button("适应窗口", systemImage: "arrow.up.left.and.arrow.down.right") { fitRequest += 1 }
                Button("100%", systemImage: "1.magnifyingglass") { zoom = 1 }
            }
            .buttonStyle(.bordered)
            .controlSize(.small)

            Button("用预览打开", systemImage: "arrow.up.forward.app") { NSWorkspace.shared.open(url) }
                .buttonStyle(.bordered)
                .controlSize(.small)
            Button { onClose?() ?? dismiss() } label: { Image(systemName: "xmark") }
                .buttonStyle(.borderless)
                .keyboardShortcut(.cancelAction)
                .help("关闭")
        }
        .padding(.horizontal, 18)
        .frame(height: 58)
    }
}

private struct ZoomableImageCanvas: View {
    let image: NSImage
    @Binding var zoom: CGFloat
    let fitRequest: Int
    @GestureState private var gestureScale: CGFloat = 1

    var body: some View {
        GeometryReader { proxy in
            let imageWidth = max(image.size.width, 1)
            let imageHeight = max(image.size.height, 1)
            let scale = max(0.1, min(8, zoom * gestureScale))
            let width = imageWidth * scale
            let height = imageHeight * scale

            ScrollView([.horizontal, .vertical]) {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: width, height: height)
                    .frame(
                        minWidth: max(proxy.size.width, width),
                        minHeight: max(proxy.size.height, height),
                        alignment: .center
                    )
            }
            .background(Color(nsColor: .underPageBackgroundColor))
            .overlay {
                ScrollWheelZoomMonitor { delta in
                    zoom = max(0.1, min(8, zoom * exp(delta)))
                }
                .accessibilityHidden(true)
            }
            .gesture(
                MagnificationGesture()
                    .updating($gestureScale) { value, state, _ in state = value }
                    .onEnded { value in zoom = max(0.1, min(8, zoom * value)) }
            )
            .onTapGesture(count: 2) {
                if abs(zoom - 1) < 0.02 { fit(in: proxy.size) }
                else { zoom = 1 }
            }
            .task(id: fitRequest) { fit(in: proxy.size) }
            .help("滚轮缩放 · 触控板捏合缩放 · 双击在 100% 与适应窗口之间切换")
        }
    }

    private func fit(in size: CGSize) {
        let availableWidth = max(size.width - 48, 1)
        let availableHeight = max(size.height - 48, 1)
        zoom = max(0.1, min(1, min(availableWidth / max(image.size.width, 1), availableHeight / max(image.size.height, 1))))
    }
}

/// 透明的 AppKit 事件桥只拦截鼠标所在图片画布内的滚轮事件，
/// 不参与命中测试，因此不会破坏双击和触控板捏合手势。
private struct ScrollWheelZoomMonitor: NSViewRepresentable {
    let onScroll: (CGFloat) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onScroll: onScroll) }

    func makeNSView(context: Context) -> MonitorView {
        let view = MonitorView()
        view.coordinator = context.coordinator
        context.coordinator.view = view
        return view
    }

    func updateNSView(_ nsView: MonitorView, context: Context) {
        context.coordinator.onScroll = onScroll
        context.coordinator.attachIfNeeded()
    }

    static func dismantleNSView(_ nsView: MonitorView, coordinator: Coordinator) {
        coordinator.detach()
    }

    final class MonitorView: NSView {
        weak var coordinator: Coordinator?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            coordinator?.attachIfNeeded()
        }

        override func hitTest(_ point: NSPoint) -> NSView? { nil }
    }

    @MainActor
    final class Coordinator {
        weak var view: MonitorView?
        var onScroll: (CGFloat) -> Void
        private var monitor: Any?
        private weak var monitoredWindow: NSWindow?

        init(onScroll: @escaping (CGFloat) -> Void) {
            self.onScroll = onScroll
        }

        func attachIfNeeded() {
            guard let view, let window = view.window else { return }
            guard monitor == nil || monitoredWindow !== window else { return }
            detach()
            monitoredWindow = window
            monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self, weak view] event in
                guard let self, let view, event.window === view.window else { return event }
                let point = view.convert(event.locationInWindow, from: nil)
                guard view.bounds.contains(point), event.momentumPhase.isEmpty else { return event }
                let delta = event.scrollingDeltaY
                guard abs(delta) > 0.01 else { return event }
                let zoomDelta: CGFloat
                if event.hasPreciseScrollingDeltas {
                    zoomDelta = max(-12, min(12, delta)) * 0.012
                } else {
                    zoomDelta = delta > 0 ? 0.12 : -0.12
                }
                self.onScroll(zoomDelta)
                return nil
            }
        }

        func detach() {
            if let monitor { NSEvent.removeMonitor(monitor) }
            monitor = nil
            monitoredWindow = nil
        }
    }
}

struct FilePreviewSheet: View {
    @Environment(\.dismiss) private var dismiss
    let url: URL
    let item: CaptureItem
    var onClose: (() -> Void)? = nil
    @State private var showsSource = false

    private var format: FileFormatDescriptor {
        .describe(url: url, fallbackExtension: item.fileExtension)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                FileTypeIcon(url: url, fallbackExtension: item.fileExtension, size: 38)
                VStack(alignment: .leading, spacing: 3) {
                    Text(item.title).font(.headline).lineLimit(1)
                    Text("\(format.formatName) · \(format.category) · \(CaptureInsightService.byteCount(item.fileSize ?? item.backupOriginalSize))")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Label(item.textFormat == nil ? format.previewDescription : "由粘贴内容自动生成", systemImage: "eye.fill")
                    .font(.caption2)
                    .foregroundStyle(.teal)
                if item.textFormat == .markdown {
                    Button(showsSource ? "渲染预览" : "查看源码", systemImage: showsSource ? "doc.richtext" : "chevron.left.forwardslash.chevron.right") {
                        showsSource.toggle()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
                Button("打开", systemImage: "arrow.up.forward.app") { NSWorkspace.shared.open(url) }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                Button("在访达显示", systemImage: "folder") { NSWorkspace.shared.activateFileViewerSelecting([url]) }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                Button { onClose?() ?? dismiss() } label: { Image(systemName: "xmark") }
                    .buttonStyle(.borderless)
                    .keyboardShortcut(.cancelAction)
                    .help("关闭")
            }
            .padding(.horizontal, 18)
            .frame(height: 62)

            Divider()
            if let textFormat = item.textFormat {
                GeneratedTextFilePreview(text: item.body, format: textFormat, showsSource: showsSource)
            } else {
                FileQuickLookPreview(url: url)
                    .id(url)
            }
        }
        .frame(minWidth: 820, minHeight: 620)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

struct GeneratedTextThumbnail: View {
    let item: CaptureItem

    var body: some View {
        ZStack(alignment: .topLeading) {
            Color(nsColor: .textBackgroundColor).opacity(0.72)
            VStack(alignment: .leading, spacing: 5) {
                HStack {
                    Label(item.textFormat?.title ?? "文本", systemImage: item.textFormat?.systemImage ?? "doc.text")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.indigo)
                    Spacer()
                    Text(".\(item.textFormat?.fileExtension ?? "txt")")
                        .font(.caption2.monospaced().weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                Divider()
                Text(item.body)
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineSpacing(3)
                    .lineLimit(7)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(10)
        }
    }
}

private struct GeneratedTextFilePreview: View {
    let text: String
    let format: TextContentFormat
    let showsSource: Bool

    private var renderedMarkdown: AttributedString {
        (try? AttributedString(markdown: text)) ?? AttributedString(text)
    }

    var body: some View {
        ScrollView([.horizontal, .vertical]) {
            Group {
                if format == .markdown && !showsSource {
                    Text(renderedMarkdown)
                        .font(.system(size: 16))
                        .lineSpacing(6)
                } else {
                    Text(text)
                        .font(.system(size: 13, design: .monospaced))
                        .lineSpacing(4)
                }
            }
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(28)
        }
        .background(Color(nsColor: .textBackgroundColor).opacity(0.42))
    }
}
