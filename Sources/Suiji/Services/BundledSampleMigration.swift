import Foundation

enum BundledSampleMigration {
    struct Result {
        let kept: [CaptureItem]
        let removed: [CaptureItem]
    }

    static func removeExamples(from items: [CaptureItem]) -> Result {
        let removed = items.filter(isBundledExample)
        return Result(
            kept: items.filter { !isBundledExample($0) },
            removed: removed
        )
    }

    static func isBundledExample(_ item: CaptureItem) -> Bool {
        switch item.kind {
        case .image:
            item.title == "海边日落的光线参考"
                && item.attachmentPath == "resource:coast-light.png"
        case .web:
            item.title == "A List Apart — Design systems are for people"
                && item.body == "https://alistapart.com"
                && item.source == "Safari 分享"
        case .text:
            item.title == "真正的专注，来自对“下一步”的清晰定义。"
                && item.body == "把大目标拆到下一步，再把这一步做到极致；重复这个循环，自然会走很远。"
        case .credential:
            item.title == "微信 · 工作号"
                && item.username == "qinghe.design"
                && item.source == "手动录入"
        case .file:
            item.title == "《纳瓦尔宝典》读书笔记.pdf"
                && item.fileName == "纳瓦尔宝典-读书笔记.pdf"
                && item.source == "访达拖入"
        }
    }
}
