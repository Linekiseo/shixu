import SwiftUI

struct TextNoteCard: View {
    @ObservedObject var store: CaptureStore
    let item: CaptureItem
    var compactLayout = false

    private var content: String {
        item.body.isEmpty ? item.title : item.body
    }

    private var documentExcerpt: String {
        guard item.textFormat != nil else { return content }
        var lines = content.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        if let first = lines.first {
            let heading = first.trimmingCharacters(in: CharacterSet(charactersIn: "# ").union(.whitespaces))
            if heading.caseInsensitiveCompare(item.title) == .orderedSame { lines.removeFirst() }
        }
        let excerpt = lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        return excerpt.isEmpty ? item.summary : excerpt
    }

    var body: some View {
        HStack(spacing: 0) {
            Rectangle()
                .fill(Color.indigo.gradient)
                .frame(width: 5)

            VStack(alignment: .leading, spacing: 11) {
                HStack(spacing: 8) {
                    if let format = item.textFormat {
                        Label("\(format.title) · .\(format.fileExtension)", systemImage: format.systemImage)
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.indigo)
                    } else {
                        Text(item.collection ?? "随想")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.indigo)
                    }
                    Text("·")
                        .foregroundStyle(.tertiary)
                    Text(item.source)
                        .lineLimit(1)
                        .layoutPriority(-1)
                    Spacer()
                    Text(item.createdAt.suijiTime)
                        .monospacedDigit()
                    favoriteButton
                }
                .font(.caption2)
                .foregroundStyle(.secondary)

                if item.textFormat != nil {
                    VStack(alignment: .leading, spacing: 7) {
                        Text(item.title)
                            .font(.custom("Songti SC", size: 18).weight(.semibold))
                            .lineLimit(2)
                        if !documentExcerpt.isEmpty {
                            Text(documentExcerpt)
                                .font(.custom("Songti SC", size: 14))
                                .foregroundStyle(.secondary)
                                .lineSpacing(4)
                                .lineLimit(3)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    Text(content)
                        .font(.custom("Songti SC", size: 17).weight(.medium))
                        .lineSpacing(5)
                        .lineLimit(4)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                HStack(spacing: 8) {
                    Label("\(content.count) 字", systemImage: "character.cursor.ibeam")
                    if item.textFormat != nil {
                        Label(CaptureInsightService.byteCount(item.fileSize), systemImage: "doc.badge.gearshape")
                    }
                    if let note = item.userNote, !note.isEmpty {
                        Label("有备注", systemImage: "pencil.line")
                    }
                    Spacer()
                    if item.textFormat != nil {
                        Button {
                            CapturePrimaryAction.preview(store: store, item: item)
                        } label: {
                            if compactLayout { Image(systemName: "eye") }
                            else { Label("预览文件", systemImage: "eye") }
                        }
                            .buttonStyle(.borderless)
                            .foregroundStyle(.indigo)
                            .disabled(store.attachmentURL(for: item) == nil)
                    }
                    if !compactLayout {
                        ForEach(item.tags.prefix(3), id: \.self) { tag in
                            Text("#\(tag)")
                        }
                    }
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 13)
        }
        .background(
            LinearGradient(
                colors: [Color(nsColor: .textBackgroundColor).opacity(0.82), Color.indigo.opacity(0.035)],
                startPoint: .leading,
                endPoint: .trailing
            ),
            in: RoundedRectangle(cornerRadius: 14)
        )
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.indigo.opacity(0.15)))
    }

    private var favoriteButton: some View {
        Button { store.toggleFavorite(item.id) } label: {
            Image(systemName: item.isFavorite ? "bookmark.fill" : "bookmark")
                .foregroundStyle(item.isFavorite ? Color.indigo : Color.secondary)
        }
        .buttonStyle(.plain)
        .help(item.isFavorite ? "取消收藏" : "收藏")
    }
}
