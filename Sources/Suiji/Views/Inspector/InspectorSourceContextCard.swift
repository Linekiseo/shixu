import SwiftUI

struct InspectorSourceContextCard: View {
    let item: CaptureItem

    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            Label("记录来源", systemImage: "arrow.down.to.line.compact")
                .font(.caption.weight(.semibold))
            if let app = item.sourceApplication {
                field("来源应用", value: app, icon: "app.badge.fill", tint: .blue)
                Text("从 \(app) 的剪贴板内容中记录")
                    .font(.caption2).foregroundStyle(.secondary)
            }
            field("记录方式", value: item.source, icon: "sensor.tag.radiowaves.forward", tint: .mint)
            field("记录时间", value: item.createdAt.formatted(date: .abbreviated, time: .standard), icon: "clock", tint: .orange)

            if let location = item.originalLocation {
                Divider()
                Link(destination: URL(fileURLWithPath: location)) {
                    Label(location, systemImage: "folder").lineLimit(2)
                }
                .font(.caption2)
            } else if let value = linkValue, let url = URL(string: value) {
                Divider()
                Link(destination: url) {
                    HStack {
                        Label(value, systemImage: "link").lineLimit(2)
                        Spacer()
                        Image(systemName: "arrow.up.right")
                    }
                }
                .font(.caption2)
            }
        }
        .padding(13)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.background.opacity(0.48), in: RoundedRectangle(cornerRadius: 11))
        .overlay(RoundedRectangle(cornerRadius: 11).stroke(SuijiTheme.divider))
    }

    private var linkValue: String? {
        if item.kind == .web { return item.body }
        return item.credentialType == .apiKey ? item.apiBaseURL : item.loginURL
    }

    private func field(_ name: String, value: String, icon: String, tint: Color) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: icon).foregroundStyle(tint).frame(width: 16)
            Text(name).font(.caption2).foregroundStyle(.tertiary).frame(width: 54, alignment: .leading)
            Text(value).font(.caption).textSelection(.enabled)
            Spacer(minLength: 0)
        }
    }
}
