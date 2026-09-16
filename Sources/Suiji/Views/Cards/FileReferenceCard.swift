import SwiftUI

struct FileReferenceCard: View {
    @ObservedObject var store: CaptureStore
    let item: CaptureItem
    var compactLayout = false

    private var resolvedURL: URL? { store.attachmentURL(for: item) }
    private var format: FileFormatDescriptor { .describe(url: resolvedURL, fallbackExtension: item.fileExtension) }

    var body: some View {
        Group {
            if compactLayout {
                VStack(spacing: 0) {
                    filePreview
                        .frame(maxWidth: .infinity)
                        .frame(height: compactPreviewHeight)
                        .background(Color.teal.opacity(0.045))
                        .clipped()
                    informationArea
                }
                .frame(maxWidth: .infinity)
            } else {
                HStack(spacing: 0) {
                    filePreview
                        .frame(width: 148, height: 132)
                        .background(Color.teal.opacity(0.045))
                    informationArea
                }
            }
        }
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.76), in: RoundedRectangle(cornerRadius: 14))
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.teal.opacity(0.2)))
        .onDrag { CaptureDragProvider.make(store: store, item: item) }
        .onTapGesture(count: 2) { CapturePrimaryAction.perform(store: store, item: item) }
        .help("可拖到访达、邮件、聊天或其他 App 直接使用原文件")
    }

    private var informationArea: some View {
        VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top, spacing: 10) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("\(format.formatName) · \(format.category)")
                            .font(.system(size: 9, weight: .bold, design: .rounded))
                            .tracking(1.4)
                            .foregroundStyle(.teal)
                        Text(item.title)
                            .font(.custom("Songti SC", size: 16).weight(.semibold))
                            .lineLimit(2)
                    }
                    Spacer()
                    Button { store.toggleFavorite(item.id) } label: {
                        Image(systemName: item.isFavorite ? "star.fill" : "star")
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(item.isFavorite ? Color.yellow : Color.secondary)
                }

                HStack(spacing: 12) {
                    Label(CaptureInsightService.byteCount(item.fileSize ?? item.backupOriginalSize), systemImage: "internaldrive")
                    Label(item.backupPath == nil ? "链接原文件" : "含压缩备份", systemImage: item.backupPath == nil ? "link" : "archivebox.fill")
                }
                .font(.caption2)
                .foregroundStyle(.secondary)

                if let path = item.originalLocation {
                    Text(URL(fileURLWithPath: path).deletingLastPathComponent().path)
                        .font(.caption2.monospaced())
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }

                HStack(spacing: 6) {
                    Circle()
                        .fill(resolvedURL == nil ? Color.orange : Color.green)
                        .frame(width: 6, height: 6)
                    Text(resolvedURL == nil ? "原文件失联" : "原文件可访问")
                    Spacer()
                    Text(item.createdAt.suijiDayLabel)
                    Button { openPreview() } label: {
                        if compactLayout { Image(systemName: "eye") }
                        else { Label("预览", systemImage: "eye") }
                    }
                        .buttonStyle(.borderless)
                        .foregroundStyle(.teal)
                        .disabled(resolvedURL == nil)
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
            }
            .padding(14)
        }

    @ViewBuilder
    private var filePreview: some View {
        if let resolvedURL {
            FileThumbnailPreview(url: resolvedURL, fallbackExtension: item.fileExtension)
                .allowsHitTesting(false)
        } else {
            VStack(spacing: 9) {
                FileTypeIcon(url: nil, fallbackExtension: item.fileExtension, size: 52)
                Text("等待重新连接")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func openPreview() {
        guard let resolvedURL else { return }
        PreviewWindowController.shared.showFile(url: resolvedURL, item: item)
    }

    private var compactPreviewHeight: CGFloat {
        if ["图像", "视频"].contains(format.category) { return 214 }
        if ["便携文档", "演示文稿"].contains(format.category) { return 196 }
        return 172
    }
}
