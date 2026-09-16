import AppKit
import SwiftUI
@preconcurrency import WebKit

struct OfflineWebArchiveSheet: View {
    @Environment(\.dismiss) private var dismiss
    let archiveURL: URL
    let liveURL: URL
    let item: CaptureItem
    @State private var loadState: OfflineArchiveLoadState = .loading
    @State private var reloadID = UUID()

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Image(systemName: "archivebox.fill")
                    .font(.title2)
                    .foregroundStyle(.green)
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.title).font(.headline).lineLimit(1)
                    Text("本机离线存档 · \(item.webArchiveCapturedAt?.formatted(date: .abbreviated, time: .shortened) ?? "保存时间未知") · \(CaptureInsightService.byteCount(item.webArchiveCompressedSize))")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Label(loadState.label, systemImage: loadState.systemImage)
                    .font(.caption2)
                    .foregroundStyle(loadState.tint)
                Button("打开在线页面", systemImage: "arrow.up.right") { NSWorkspace.shared.open(liveURL) }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                Button { dismiss() } label: { Image(systemName: "xmark") }
                    .buttonStyle(.borderless)
                    .keyboardShortcut(.cancelAction)
            }
            .padding(.horizontal, 17)
            .frame(height: 60)
            Divider()
            ZStack {
                ArchivedWebView(
                    url: archiveURL,
                    onReady: { loadState = .ready },
                    onFailure: { loadState = .failed($0) }
                )
                .id(reloadID)

                if case .loading = loadState {
                    VStack(spacing: 12) {
                        ProgressView().controlSize(.large)
                        Text("正在整理本机网页快照…")
                            .font(.headline)
                        Text("不会连接或刷新原网站")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(24)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
                } else if case let .failed(message) = loadState {
                    ContentUnavailableView {
                        Label("离线快照暂时无法显示", systemImage: "archivebox")
                    } description: {
                        Text(message)
                    } actions: {
                        Button("重新载入", systemImage: "arrow.clockwise") {
                            loadState = .loading
                            reloadID = UUID()
                        }
                    }
                }
            }
        }
        .frame(minWidth: 940, minHeight: 700)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

private struct ArchivedWebView: NSViewRepresentable {
    let url: URL
    let onReady: @MainActor () -> Void
    let onFailure: @MainActor (String) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onReady: onReady, onFailure: onFailure)
    }

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = false
        let view = WKWebView(frame: .zero, configuration: configuration)
        view.navigationDelegate = context.coordinator
        view.allowsMagnification = true
        view.underPageBackgroundColor = .windowBackgroundColor
        view.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
        return view
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {}

    @MainActor
    final class Coordinator: NSObject, WKNavigationDelegate {
        private let onReady: @MainActor () -> Void
        private let onFailure: @MainActor (String) -> Void

        init(
            onReady: @escaping @MainActor () -> Void,
            onFailure: @escaping @MainActor (String) -> Void
        ) {
            self.onReady = onReady
            self.onFailure = onFailure
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            // Dynamic sites such as Discourse save their rendered DOM together with a
            // loading/skeleton layer. Page JavaScript is intentionally disabled in the
            // offline viewer, so normalize that frozen DOM ourselves and start at the
            // first captured content instead of the saved scroll position.
            webView.evaluateJavaScript(WebArchiveOfflinePresentation.normalizationScript) { [weak self] _, error in
                guard let self else { return }
                if let error {
                    self.onFailure("快照内容读取失败：\(error.localizedDescription)")
                } else {
                    self.onReady()
                }
            }
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            onFailure(error.localizedDescription)
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            onFailure(error.localizedDescription)
        }

        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction,
            decisionHandler: @escaping @MainActor (WKNavigationActionPolicy) -> Void
        ) {
            guard let scheme = navigationAction.request.url?.scheme?.lowercased() else {
                decisionHandler(.cancel)
                return
            }
            decisionHandler(scheme == "file" || scheme == "about" || scheme == "data" ? .allow : .cancel)
        }

    }
}

private enum OfflineArchiveLoadState {
    case loading
    case ready
    case failed(String)

    var label: String {
        switch self {
        case .loading: "正在读取本机快照"
        case .ready: "本机快照 · 已断开原站"
        case .failed: "本机快照读取失败"
        }
    }

    var systemImage: String {
        switch self {
        case .loading: "arrow.triangle.2.circlepath"
        case .ready: "network.slash"
        case .failed: "exclamationmark.triangle.fill"
        }
    }

    var tint: Color {
        switch self {
        case .loading: .secondary
        case .ready: .green
        case .failed: .orange
        }
    }
}
