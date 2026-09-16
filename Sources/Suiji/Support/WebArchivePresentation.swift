import SwiftUI

extension WebArchiveState {
    var title: String {
        switch self {
        case .queued: "已存链接"
        case .capturing: "正在备份"
        case .archived: "本机存档"
        case .loginRequired: "需要登录"
        case .failed: "已存链接"
        }
    }

    var systemImage: String {
        switch self {
        case .queued: "link.circle.fill"
        case .capturing: "arrow.triangle.2.circlepath"
        case .archived: "checkmark.icloud.fill"
        case .loginRequired: "person.crop.circle.badge.exclamationmark"
        case .failed: "link.circle.fill"
        }
    }

    var tint: Color {
        switch self {
        case .queued: .secondary
        case .capturing: .blue
        case .archived: .green
        case .loginRequired: .orange
        case .failed: .secondary
        }
    }
}

struct WebArchiveStatusBadge: View {
    let item: CaptureItem

    private var state: WebArchiveState { item.webArchiveState ?? .queued }

    var body: some View {
        Label(state.title, systemImage: state.systemImage)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(state.tint)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(state.tint.opacity(0.1), in: Capsule())
    }
}

enum WebArchiveOfflinePresentation {
    static let normalizationScript = #"""
    (() => {
      const styleID = 'shixu-offline-normalization';
      if (!document.getElementById(styleID)) {
        const style = document.createElement('style');
        style.id = styleID;
        style.textContent = `
          .loading-indicator-container,
          .loading-container,
          .spinner-container,
          .spinner,
          [class*="page-loading"] { display: none !important; }
          .post-stream--cloaked { display: none !important; }
          html, body { overflow: auto !important; }
          *, *::before, *::after {
            animation-duration: 0s !important;
            animation-delay: 0s !important;
            transition-duration: 0s !important;
          }
        `;
        (document.head || document.documentElement).appendChild(style);
      }

      document.documentElement.classList.remove('loading', 'is-loading');
      document.body?.classList.remove('loading', 'is-loading');
      document.querySelectorAll('[aria-busy="true"]').forEach(node => {
        node.setAttribute('aria-busy', 'false');
      });
      document.querySelectorAll('img[loading="lazy"]').forEach(image => {
        image.loading = 'eager';
        if (!image.getAttribute('src') && image.dataset?.src) image.src = image.dataset.src;
      });

      window.scrollTo(0, 0);
      requestAnimationFrame(() => window.scrollTo(0, 0));
      return document.body?.innerText?.trim().length || 0;
    })()
    """#
}
