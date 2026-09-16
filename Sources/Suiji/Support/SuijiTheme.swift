import SwiftUI

enum SuijiTheme {
    static let accent = Color(red: 0.89, green: 0.28, blue: 0.18)
    static let paper = Color(nsColor: .textBackgroundColor).opacity(0.38)
    static let ink = Color.primary
    static let divider = Color.primary.opacity(0.11)

    static let contentFont = Font.custom("Songti SC", size: 14)
    static let titleFont = Font.custom("Songti SC", size: 26).weight(.semibold)
    static let cardRadius: CGFloat = 12
}

extension CaptureKind {
    var tint: Color {
        switch self {
        case .text: .indigo
        case .image: .orange
        case .web: .blue
        case .credential: SuijiTheme.accent
        case .file: .teal
        }
    }

    var cardLabel: String {
        switch self {
        case .text: "想法"
        case .image: "画面"
        case .web: "网页"
        case .credential: "保险箱"
        case .file: "本地文件"
        }
    }
}

extension Date {
    var suijiTime: String {
        formatted(date: .omitted, time: .shortened)
    }

    var suijiDayLabel: String {
        if Calendar.current.isDateInToday(self) { return "今天" }
        if Calendar.current.isDateInYesterday(self) { return "昨天" }
        return formatted(.dateTime.month().day())
    }
}
