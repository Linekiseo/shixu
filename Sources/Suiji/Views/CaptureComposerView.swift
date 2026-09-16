import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct CaptureComposerView: View {
    @ObservedObject var store: CaptureStore
    @State private var text = ""
    @State private var forcedKind: CaptureKind?
    @State private var isDropTarget = false
    @State private var isShowingCredentialCapture = false

    private var detectedKind: CaptureKind {
        forcedKind ?? ContentDetector.inferredKind(for: text)
    }

    private var detectedFormat: TextContentFormat? {
        detectedKind == .text ? TextFormatDetector.detect(text) : nil
    }

    private var detectionLabel: String {
        if let apiKey = LLMAPIKeyDetector.detect(in: text) {
            return "识别为 \(apiKey.provider ?? "LLM") API 密钥"
        }
        return detectedFormat.map { "将保存为 \($0.title) · .\($0.fileExtension)" } ?? "识别为\(detectedKind.title)"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("快速收集", systemImage: "sparkles")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                if !text.isEmpty {
                    Label(
                        detectionLabel,
                        systemImage: detectedFormat?.systemImage ?? detectedKind.systemImage
                    )
                        .font(.caption2)
                        .foregroundStyle(detectedFormat == nil ? detectedKind.tint : Color.indigo)
                }
            }

            ZStack(alignment: .topLeading) {
                if text.isEmpty {
                    Text("输入、粘贴或拖入任何值得留下的内容…")
                        .font(SuijiTheme.contentFont)
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 7)
                }

                TextEditor(text: $text)
                    .font(SuijiTheme.contentFont)
                    .scrollContentBackground(.hidden)
                    .frame(minHeight: 42, maxHeight: 72)
            }

            Divider().opacity(0.7)

            HStack(spacing: 4) {
                ComposerAction(title: "截屏", systemImage: "viewfinder") {
                    ScreenshotService.shared.captureInteractive {
                        store.importCurrentClipboard()
                    }
                }

                ComposerAction(title: "剪贴板", systemImage: "doc.on.clipboard") {
                    store.importCurrentClipboard()
                }

                ComposerAction(title: "网页", systemImage: "link", selected: forcedKind == .web) {
                    forcedKind = forcedKind == .web ? nil : .web
                }

                ComposerAction(title: "文件", systemImage: "paperclip") {
                    chooseFile()
                }

                ComposerAction(title: "账号", systemImage: "lock") {
                    isShowingCredentialCapture = true
                }

                Spacer()

                Button("收下", systemImage: "arrow.up") {
                    submit()
                }
                .buttonStyle(.borderedProminent)
                .tint(.primary)
                .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .keyboardShortcut(.return, modifiers: [.command])
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 13)
                .fill(SuijiTheme.paper)
                .stroke(isDropTarget ? SuijiTheme.accent : SuijiTheme.divider, lineWidth: isDropTarget ? 2 : 1)
        )
        .shadow(color: .black.opacity(0.035), radius: 8, y: 2)
        .dropDestination(for: URL.self) { urls, _ in
            for url in urls { store.capture(fileURL: url) }
            return !urls.isEmpty
        } isTargeted: { isDropTarget = $0 }
        .sheet(isPresented: $isShowingCredentialCapture) {
            CredentialCaptureSheet(store: store)
        }
    }

    private func submit() {
        let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return }
        store.capture(text: text, forcedKind: forcedKind, source: "主窗口")
        text = ""
        forcedKind = nil
    }

    private func chooseFile() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        if panel.runModal() == .OK {
            panel.urls.forEach { store.capture(fileURL: $0, source: "系统文件选择器") }
        }
    }
}

private struct ComposerAction: View {
    let title: String
    let systemImage: String
    var selected = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.caption)
        }
        .buttonStyle(.borderless)
        .foregroundStyle(selected ? SuijiTheme.accent : .secondary)
        .padding(.horizontal, 5)
        .padding(.vertical, 4)
        .background(selected ? SuijiTheme.accent.opacity(0.08) : .clear, in: RoundedRectangle(cornerRadius: 5))
    }
}
