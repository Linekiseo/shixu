import SwiftUI

struct TimelineSectionHeader<SectionModel: TimelineSectionPresenting>: View {
    let section: SectionModel
    var tint: Color = .accentColor
    var compact = false

    var body: some View {
        HStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(tint.opacity(0.14))
                    .frame(width: compact ? 22 : 26, height: compact ? 22 : 26)
                Circle()
                    .fill(tint)
                    .frame(width: 7, height: 7)
            }

            VStack(alignment: .leading, spacing: 1) {
                Text(section.title)
                    .font(.custom("Songti SC", size: compact ? 15 : 17).weight(.semibold))
                if !compact {
                    Text(section.dateDetail)
                        .font(.system(size: 9))
                        .foregroundStyle(.tertiary)
                }
            }

            Rectangle()
                .fill(tint.opacity(0.14))
                .frame(height: 1)

            Text(section.timeRange)
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.tertiary)
            Text("\(section.recordCount) 条")
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, compact ? 4 : 7)
        .background(.background.opacity(0.94))
    }
}

struct LibraryEmptyState: View {
    let icon: String
    let title: String
    let description: String
    var actionTitle: String?
    var actionIcon: String = "plus"
    var action: (() -> Void)?

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 28, weight: .light))
                .foregroundStyle(.secondary)
                .frame(width: 58, height: 58)
                .background(.quaternary.opacity(0.28), in: RoundedRectangle(cornerRadius: 15))

            VStack(spacing: 5) {
                Text(title)
                    .font(.custom("Songti SC", size: 18).weight(.semibold))
                Text(description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 340)
            }

            if let actionTitle, let action {
                Button(actionTitle, systemImage: actionIcon, action: action)
                    .buttonStyle(.bordered)
            }
        }
        .padding(26)
        .background(.quaternary.opacity(0.11), in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(SuijiTheme.divider))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(28)
    }
}
