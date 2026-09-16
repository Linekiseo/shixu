import AppKit
import SwiftUI

struct VerticalScrollIndicatorSuppressor: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        ScrollIndicatorProbe()
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        (nsView as? ScrollIndicatorProbe)?.suppressIndicator()
    }
}

private final class ScrollIndicatorProbe: NSView {
    private var updateScheduled = false

    override func viewDidMoveToSuperview() {
        super.viewDidMoveToSuperview()
        suppressIndicator()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        suppressIndicator()
    }

    override func layout() {
        super.layout()
        suppressIndicator()
    }

    func suppressIndicator() {
        guard !updateScheduled else { return }
        updateScheduled = true
        Task { @MainActor [weak self] in
            await Task.yield()
            guard let self else { return }
            updateScheduled = false
            guard let scrollView = enclosingScrollView else { return }
            if scrollView.hasVerticalScroller { scrollView.hasVerticalScroller = false }
            if scrollView.verticalScroller?.isHidden == false { scrollView.verticalScroller?.isHidden = true }
            if !scrollView.autohidesScrollers { scrollView.autohidesScrollers = true }
        }
    }
}
