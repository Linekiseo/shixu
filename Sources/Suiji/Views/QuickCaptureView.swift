import AppKit
import SwiftUI

struct QuickCaptureView: View {
    @ObservedObject var store: CaptureStore
    @State private var text = ""
    @State private var forcedKind: CaptureKind?
    @State private var isShowingCredentialCapture = false
    @FocusState private var focused: Bool

    private var detectedKind: CaptureKind {
        forcedKind ?? ContentDetector.inferredKind(for: text)
    }

    private var detectedFormat: TextContentFormat? {
        detectedKind == .text ? TextFormatDetector.detect(text) : nil
    }

    private var detectionLabel: String {
        if let apiKey = LLMAPIKeyDetector.detect(in: text) {
            return "将安全保存为「\(apiKey.provider ?? "LLM") API 密钥」"
        }
        return detectedFormat.map { "将保存为 \($0.title) · .\($0.fileExtension)" } ?? "将识别为「\(detectedKind.title)」"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label("随手放进来，剩下的交给\(AppBrand.displayName)", systemImage: "wand.and.stars")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text("⌘ ⇧ Space")
                    .font(.caption2.monospaced())
                    .foregroundStyle(.tertiary)
            }

            ZStack(alignment: .topLeading) {
                if text.isEmpty {
                    Text("记点什么，或直接粘贴文字、链接、账号信息…")
                        .font(.custom("Songti SC", size: 17))
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 7)
                }

                TextEditor(text: $text)
                    .font(.custom("Songti SC", size: 17))
                    .scrollContentBackground(.hidden)
                    .focused($focused)
                    .frame(minHeight: 104)
            }

            if let candidate = store.clipboardCandidate {
                Button {
                    store.capture(candidate: candidate, source: "快速记录面板")
                    QuickCapturePanelController.shared.hide()
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: candidate.kind.systemImage).foregroundStyle(SuijiTheme.accent)
                        Text("保存剪贴板：\(candidate.displayText)").lineLimit(1)
                        Spacer()
                        Image(systemName: "arrow.up.right")
                    }
                    .font(.caption)
                }
                .buttonStyle(.plain)
                .padding(9)
                .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 6))
            }

            HStack(spacing: 12) {
                Button("粘贴", systemImage: "doc.on.clipboard") {
                    if let value = NSPasteboard.general.string(forType: .string) { text = value }
                }
                .buttonStyle(.borderless)

                Button("账号", systemImage: "lock") {
                    isShowingCredentialCapture = true
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)

                Button("文件", systemImage: "paperclip") { chooseFile() }
                    .buttonStyle(.borderless)

                Spacer()

                if !text.isEmpty {
                    Text(detectionLabel)
                        .font(.caption2)
                        .foregroundStyle(detectedFormat == nil ? AnyShapeStyle(.tertiary) : AnyShapeStyle(Color.indigo))
                }

                Button("保存") { submit() }
                    .buttonStyle(.borderedProminent)
                    .tint(.primary)
                    .keyboardShortcut(.return, modifiers: [.command])
                    .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }

            HStack(spacing: 14) {
                Text("⌘ ↵ 保存")
                Text("Esc 关闭")
                Spacer()
                Text("内容默认只保存在本机")
            }
            .font(.system(size: 9))
            .foregroundStyle(.tertiary)
        }
        .padding(22)
        .frame(width: 640, height: 310)
        .background(.thickMaterial)
        .onAppear {
            focused = true
            ClipboardMonitor.shared.poll(store: store, force: true)
        }
        .onExitCommand { QuickCapturePanelController.shared.hide() }
        .sheet(isPresented: $isShowingCredentialCapture) {
            CredentialCaptureSheet(store: store) {
                QuickCapturePanelController.shared.hide()
            }
        }
    }

    private func submit() {
        let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return }
        store.capture(text: text, forcedKind: forcedKind, source: "全局快捷记录")
        text = ""
        forcedKind = nil
        QuickCapturePanelController.shared.hide()
    }

    private func chooseFile() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        if panel.runModal() == .OK {
            panel.urls.forEach { store.capture(fileURL: $0, source: "快速记录面板") }
            QuickCapturePanelController.shared.hide()
        }
    }
}
