import Foundation

enum SidebarCategory: String, CaseIterable, Identifiable, Hashable {
    case inbox
    case all
    case images
    case web
    case credentials
    case files
    case compositions
    case favorites
    case monitoring
    case trash

    var id: String { rawValue }

    var title: String {
        switch self {
        case .inbox: "收件箱"
        case .all: "全部"
        case .images: "图片与截图"
        case .web: "网页"
        case .credentials: "账号"
        case .files: "文件"
        case .compositions: "组合"
        case .favorites: "收藏"
        case .monitoring: "系统监测"
        case .trash: "回收站"
        }
    }

    var systemImage: String {
        switch self {
        case .inbox: "tray"
        case .all: "square.grid.2x2"
        case .images: "photo"
        case .web: "globe"
        case .credentials: "person.crop.circle"
        case .files: "doc"
        case .compositions: "square.stack.3d.up.fill"
        case .favorites: "star"
        case .monitoring: "waveform.path.ecg"
        case .trash: "trash"
        }
    }

    func includes(_ item: CaptureItem) -> Bool {
        switch self {
        case .inbox: !item.isDeleted
        case .all: !item.isDeleted
        case .images: !item.isDeleted && item.kind == .image
        case .web: !item.isDeleted && item.kind == .web
        case .credentials: !item.isDeleted && item.kind == .credential
        case .files: !item.isDeleted && (item.kind == .file || item.textFormat != nil)
        case .compositions: !item.isDeleted && item.compositionID != nil
        case .favorites: !item.isDeleted && item.isFavorite
        case .monitoring: false
        case .trash: item.isDeleted
        }
    }
}
