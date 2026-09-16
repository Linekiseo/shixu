import Foundation
@preconcurrency import WebKit

enum WebArchiveCaptureResult: Sendable {
    case archived(data: Data, title: String?, finalURL: URL?)
    case loginRequired(message: String)
    case failed(message: String)
}

@MainActor
final class WebArchiveCaptureService: NSObject, WKNavigationDelegate {
    static let shared = WebArchiveCaptureService()

    private struct Job {
        let itemID: UUID
        let url: URL
        let completion: @MainActor (WebArchiveCaptureResult) -> Void
    }

    private var queue: [Job] = []
    private var activeJob: Job?
    private var webView: WKWebView?
    private var timeoutTask: Task<Void, Never>?
    private var responseStatusCode: Int?
    private var isFinishing = false

    func enqueue(
        itemID: UUID,
        url: URL,
        completion: @escaping @MainActor (WebArchiveCaptureResult) -> Void
    ) {
        guard activeJob?.itemID != itemID, !queue.contains(where: { $0.itemID == itemID }) else { return }
        queue.append(Job(itemID: itemID, url: url, completion: completion))
        startNextIfNeeded()
    }

    func cancel(itemID: UUID) {
        queue.removeAll { $0.itemID == itemID }
        guard activeJob?.itemID == itemID else { return }
        complete(.failed(message: "归档已取消"))
    }

    private func startNextIfNeeded() {
        guard activeJob == nil, !queue.isEmpty else { return }
        let job = queue.removeFirst()
        activeJob = job
        responseStatusCode = nil
        isFinishing = false

        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        let webView = WKWebView(frame: CGRect(x: 0, y: 0, width: 1_280, height: 900), configuration: configuration)
        webView.navigationDelegate = self
        self.webView = webView
        webView.load(URLRequest(url: job.url, cachePolicy: .useProtocolCachePolicy, timeoutInterval: 30))

        timeoutTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(35))
            guard !Task.isCancelled, let self, self.activeJob?.itemID == job.itemID else { return }
            self.complete(.failed(message: "网页加载超时，可稍后重试或打开站点会话"))
        }
    }

    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationResponse: WKNavigationResponse,
        decisionHandler: @escaping @MainActor (WKNavigationResponsePolicy) -> Void
    ) {
        if navigationResponse.isForMainFrame,
           let response = navigationResponse.response as? HTTPURLResponse {
            responseStatusCode = response.statusCode
        }
        decisionHandler(.allow)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        guard !isFinishing else { return }
        isFinishing = true
        Task { [weak self] in await self?.finishLoadedPage() }
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        guard !isFinishing else { return }
        complete(.failed(message: "网页加载失败：\(error.localizedDescription)"))
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        guard !isFinishing else { return }
        complete(.failed(message: "无法访问网页：\(error.localizedDescription)"))
    }

    private func finishLoadedPage() async {
        guard let webView, let job = activeJob else { return }
        try? await Task.sleep(for: .milliseconds(1_200))
        guard activeJob?.itemID == job.itemID else { return }

        let accessCheck = await pageAccessCheck(in: webView)
        switch WebArchiveAccessPolicy.decision(
            statusCode: responseStatusCode,
            looksLikeLogin: accessCheck.looksLikeLogin,
            looksLikePrivateMissingPage: accessCheck.privateMissing
        ) {
        case .loginRequired:
            complete(.loginRequired(message: "站点要求登录后才能读取这篇内容"))
            return
        case let .failedStatus(statusCode):
            complete(.failed(message: "站点返回 HTTP \(statusCode)，没有生成无效的离线存档"))
            return
        case .archive:
            break
        }

        await prepareLazyContent(in: webView)
        guard activeJob?.itemID == job.itemID else { return }

        do {
            let data = try await webArchiveData(from: webView)
            guard !data.isEmpty else {
                complete(.failed(message: "网页没有生成可用的离线存档"))
                return
            }
            complete(.archived(data: data, title: webView.title, finalURL: webView.url))
        } catch {
            complete(.failed(message: "离线存档生成失败：\(error.localizedDescription)"))
        }
    }

    private func pageAccessCheck(in webView: WKWebView) async -> LoginPageCheck {
        let script = #"""
        (() => {
          const href = (location.href || '').toLowerCase();
          const path = (location.pathname || '').toLowerCase();
          const visiblePassword = Array.from(document.querySelectorAll('input[type="password"]'))
            .some(el => !!(el.offsetWidth || el.offsetHeight || el.getClientRects().length));
          const body = (document.body?.innerText || '').trim();
          const loginPath = /(^|\/)(login|signin|sign-in|auth)(\/|$)/.test(path);
          const shortLoginWall = body.length < 4000 && /(请先登录|登录后查看|需要登录|sign in to continue|log in to continue)/i.test(body);
          const privateMissing = body.length < 8000 && /(找不到页面|页面不存在或无权访问|doesn.?t exist or is private|page is private|需要权限|无权访问)/i.test(body);
          return JSON.stringify({ visiblePassword, loginPath, shortLoginWall, privateMissing, href });
        })()
        """#
        guard let value = try? await webView.evaluateJavaScript(script) as? String,
              let data = value.data(using: .utf8),
              let result = try? JSONDecoder().decode(LoginPageCheck.self, from: data) else {
            return LoginPageCheck(visiblePassword: false, loginPath: false, shortLoginWall: false, privateMissing: false)
        }
        return result
    }

    private func prepareLazyContent(in webView: WKWebView) async {
        let script = #"""
        const viewport = Math.max(window.innerHeight, 600);
        const limit = Math.min(document.documentElement.scrollHeight, viewport * 18);
        for (let y = 0; y < limit; y += viewport) {
          window.scrollTo(0, y);
          await new Promise(resolve => setTimeout(resolve, 110));
        }
        window.scrollTo(0, 0);
        await new Promise(resolve => setTimeout(resolve, 650));
        document.querySelectorAll('img[loading="lazy"]').forEach(image => {
          image.loading = 'eager';
        });
        return true;
        """#
        _ = try? await webView.callAsyncJavaScript(script, arguments: [:], in: nil, contentWorld: .page)
    }

    private func webArchiveData(from webView: WKWebView) async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            webView.createWebArchiveData { result in
                continuation.resume(with: result)
            }
        }
    }

    private func complete(_ result: WebArchiveCaptureResult) {
        guard let job = activeJob else { return }
        timeoutTask?.cancel()
        timeoutTask = nil
        webView?.stopLoading()
        webView?.navigationDelegate = nil
        webView = nil
        activeJob = nil
        responseStatusCode = nil
        isFinishing = false
        job.completion(result)
        startNextIfNeeded()
    }
}

private struct LoginPageCheck: Decodable {
    let visiblePassword: Bool
    let loginPath: Bool
    let shortLoginWall: Bool
    let privateMissing: Bool

    var looksLikeLogin: Bool {
        visiblePassword || loginPath || shortLoginWall
    }
}
