import Foundation

enum FileStorageMode: String, CaseIterable, Identifiable {
    case linked
    case compressedBackup

    var id: String { rawValue }

    var title: String {
        switch self {
        case .linked: "仅引用原文件"
        case .compressedBackup: "引用并压缩备份"
        }
    }

    var detail: String {
        switch self {
        case .linked: "不复制文件；移动后尝试通过系统书签继续追踪。"
        case .compressedBackup: "保留原文件引用，同时创建 LZFSE 无损压缩备份。"
        }
    }
}
