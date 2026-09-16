import AppKit
import Combine
import SwiftUI
@preconcurrency import WebKit

struct WebsiteSessionArchiveSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var store: CaptureStore
    let item: CaptureItem
    @StateObject private var browser: WebsiteSessionController
    @State private var isArchiving = false

    init(store: CaptureStore, item: CaptureItem) {
        self.store = store
        self.item = item
        let url = URL(string: item.body) ?? URL(string: "about:blank")!
        _browser = StateObject(wrappedValue: WebsiteSessionController(url: url))
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if let errorMessage = browser.errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .padding(9)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.orange.opacity(0.08))
            }
            WebsiteSessionWebView(controller: browser)
        }
        .frame(minWidth: 940, minHeight: 700)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var header: some View {
        VStack(spacing: 9) {
            HStack(spacing: 10) {
                Button { browser.goBack() } label: { Image(systemName: "chevron.left") }
                    .disabled(!browser.canGoBack)
                Button { browser.goForward() } label: { Image(systemName: "chevron.right") }
                    .disabled(!browser.canGoForward)
                Button { browser.reload() } label: { Image(systemName: "arrow.clockwise") }
                Button("返回原页面", systemImage: "arrow.uturn.backward") { browser.returnToOriginalPage() }
                Divider().frame(height: 22)

                VStack(alignment: .leading, spacing: 2) {
                    Text(browser.pageTitle.isEmpty ? (item.webRootDomain ?? item.domain ?? "站点会话") : browser.pageTitle)
                        .font(.headline)
                        .lineLimit(1)
                    Text(browser.currentURL?.absoluteString ?? item.body)
                        .font(.caption2.monospaced())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer()

                if browser.isLoading { ProgressView().controlSize(.small) }
                Button(isArchiving ? "正在保存…" : "完成登录并备份当前页", systemImage: "archivebox.fill") {
                    archiveCurrentPage()
                }
                .buttonStyle(.borderedProminent)
                .tint(.blue)
                .disabled(browser.isLoading || isArchiving)
                Button { dismiss() } label: { Image(systemName: "xmark") }
                    .buttonStyle(.borderless)
                    .keyboardShortcut(.cancelAction)
            }

            HStack(spacing: 7) {
                Image(systemName: "person.badge.shield.checkmark.fill")
                    .foregroundStyle(.green)
                Text("在这里登录 \(item.webRootDomain ?? item.domain ?? "该站点") 一次，同一根网站会复用登录状态；密码只提交给网站，不写入拾序记录。")
                Spacer()
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .padding(.horizontal, 16)
        .padding(.vertical, 11)
    }

    private func archiveCurrentPage() {
        isArchiving = true
        browser.createArchive { result in
            isArchiving = false
            switch result {
            case let .success(data):
                store.storeAuthenticatedWebArchive(
                    data,
                    for: item.id,
                    pageTitle: browser.pageTitle,
                    finalURL: browser.currentURL
                )
                dismiss()
            case let .failure(error):
                browser.errorMessage = "存档生成失败：\(error.localizedDescription)"
            }
        }
    }
}

@MainActor
final class WebsiteSessionController: NSObject, ObservableObject, WKNavigationDelegate, WKUIDelegate {
    @Published var pageTitle = ""
    @Published var currentURL: URL?
    @Published var isLoading = false
    @Published var canGoBack = false
    @Published var canGoForward = false
    @Published var errorMessage: String?

    let originalURL: URL
    let webView: WKWebView

    init(url: URL) {
        originalURL = url
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        webView = WKWebView(frame: .zero, configuration: configuration)
        super.init()
        webView.navigationDelegate = self
        webView.uiDelegate = self
        webView.allowsMagnification = true
        load(url)
    }

    func load(_ url: URL) {
        errorMessage = nil
        webView.load(URLRequest(url: url, cachePolicy: .useProtocolCachePolicy, timeoutInterval: 45))
    }

    func goBack() { if webView.canGoBack { webView.goBack() } }
    func goForward() { if webView.canGoForward { webView.goForward() } }
    func reload() { webView.reload() }
    func returnToOriginalPage() { load(originalURL) }

    func createArchive(completion: @escaping @MainActor (Result<Data, Error>) -> Void) {
        Task {
            let script = #"""
            (() => {
              const title = (document.title || '').toLowerCase();
              const hasVisiblePassword = Array.from(document.querySelectorAll('input[type="password"]'))
                .some(el => !!(el.offsetWidth || el.offsetHeight || el.getClientRects().length));
              const hasChallenge = !!document.querySelector('iframe[src*="challenges.cloudflare.com"], iframe[src*="turnstile"]');
              const accessWallTitle = /(请稍候|just a moment|找不到页面|not found|sign in|log in)/i.test(title);
              return hasVisiblePassword || hasChallenge || accessWallTitle;
            })()
            """#
            let pageIsNotReady = (try? await webView.evaluateJavaScript(script) as? Bool) ?? false
            guard !pageIsNotReady else {
                completion(.failure(WebsiteSessionArchiveError.pageStillRequiresAuthentication))
                return
            }
            await preparePageForStaticArchive()
            webView.createWebArchiveData(completionHandler: completion)
        }
    }

    private func preparePageForStaticArchive() async {
        let script = #"""
        const viewport = Math.max(window.innerHeight, 600);
        const limit = Math.min(document.documentElement.scrollHeight, viewport * 18);
        for (let y = 0; y < limit; y += viewport) {
          window.scrollTo(0, y);
          await new Promise(resolve => setTimeout(resolve, 100));
        }
        window.scrollTo(0, 0);
        await new Promise(resolve => setTimeout(resolve, 650));
        document.querySelectorAll('img[loading="lazy"]').forEach(image => {
          image.loading = 'eager';
        });
        return true;
        """#
        _ = try? await webView.callAsyncJavaScript(
            script,
            arguments: [:],
            in: nil,
            contentWorld: .page
        )
    }

    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        isLoading = true
        errorMessage = nil
        refreshState()
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        isLoading = false
        refreshState()
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        isLoading = false
        errorMessage = error.localizedDescription
        refreshState()
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        isLoading = false
        errorMessage = error.localizedDescription
        refreshState()
    }

    func webView(
        _ webView: WKWebView,
        createWebViewWith configuration: WKWebViewConfiguration,
        for navigationAction: WKNavigationAction,
        windowFeatures: WKWindowFeatures
    ) -> WKWebView? {
        if navigationAction.targetFrame == nil, let url = navigationAction.request.url { load(url) }
        return nil
    }

    private func refreshState() {
        pageTitle = webView.title ?? ""
        currentURL = webView.url
        canGoBack = webView.canGoBack
        canGoForward = webView.canGoForward
    }
}

private enum WebsiteSessionArchiveError: LocalizedError {
    case pageStillRequiresAuthentication

    var errorDescription: String? {
        "页面仍停留在登录、安全质询或访问墙；请完成验证并返回原帖子后再备份。"
    }
}

private struct WebsiteSessionWebView: NSViewRepresentable {
    @ObservedObject var controller: WebsiteSessionController

    func makeNSView(context: Context) -> WKWebView { controller.webView }
    func updateNSView(_ nsView: WKWebView, context: Context) {}
}
