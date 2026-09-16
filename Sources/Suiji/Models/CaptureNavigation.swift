import Foundation

enum CaptureDestination: Hashable, Identifiable {
    case category(SidebarCategory)
    case collection(String)

    var id: String {
        switch self {
        case .category(let category): "category:\(category.rawValue)"
        case .collection(let collection): "collection:\(collection)"
        }
    }

    var category: SidebarCategory {
        switch self {
        case .category(let category): category
        case .collection: .all
        }
    }

    var collection: String? {
        guard case .collection(let collection) = self else { return nil }
        return collection
    }

    func includes(_ item: CaptureItem) -> Bool {
        guard category.includes(item) else { return false }
        guard let collection else { return true }
        return item.collection == collection
    }
}

struct CaptureNavigation: Equatable {
    var destination: CaptureDestination
    var selectedItemID: CaptureItem.ID?
}
