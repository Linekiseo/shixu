import SwiftUI

struct MasonryLayout: Layout {
    var minimumColumnWidth: CGFloat = 340
    var maximumColumns = 3
    var spacing: CGFloat = 14

    struct Cache {
        var width: CGFloat = -1
        var sizes: [CGSize] = []
        var origins: [CGPoint] = []
        var height: CGFloat = 0
        var columnWidth: CGFloat = 0
    }

    func makeCache(subviews: Subviews) -> Cache { Cache() }

    func sizeThatFits(
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout Cache
    ) -> CGSize {
        let width = resolvedWidth(proposal.width)
        calculate(width: width, subviews: subviews, cache: &cache)
        return CGSize(width: width, height: cache.height)
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout Cache
    ) {
        let width = max(1, bounds.width)
        if abs(cache.width - width) > 0.5 || cache.sizes.count != subviews.count {
            calculate(width: width, subviews: subviews, cache: &cache)
        }
        for index in subviews.indices where index < cache.origins.count {
            let origin = cache.origins[index]
            subviews[index].place(
                at: CGPoint(x: bounds.minX + origin.x, y: bounds.minY + origin.y),
                anchor: .topLeading,
                proposal: ProposedViewSize(width: cache.columnWidth, height: cache.sizes[index].height)
            )
        }
    }

    private func resolvedWidth(_ proposed: CGFloat?) -> CGFloat {
        guard let proposed, proposed.isFinite, proposed > 0 else { return minimumColumnWidth }
        return proposed
    }

    private func calculate(width: CGFloat, subviews: Subviews, cache: inout Cache) {
        let columns = max(1, min(maximumColumns, Int((width + spacing) / (minimumColumnWidth + spacing))))
        let columnWidth = max(1, (width - CGFloat(columns - 1) * spacing) / CGFloat(columns))
        var heights = Array(repeating: CGFloat.zero, count: columns)
        var sizes: [CGSize] = []
        var origins: [CGPoint] = []

        for subview in subviews {
            let measured = subview.sizeThatFits(ProposedViewSize(width: columnWidth, height: nil))
            let height = measured.height.isFinite ? max(1, measured.height) : 1
            let column = heights.enumerated().min { $0.element < $1.element }?.offset ?? 0
            origins.append(CGPoint(x: CGFloat(column) * (columnWidth + spacing), y: heights[column]))
            sizes.append(CGSize(width: columnWidth, height: height))
            heights[column] += height + spacing
        }

        cache.width = width
        cache.columnWidth = columnWidth
        cache.sizes = sizes
        cache.origins = origins
        cache.height = max(0, (heights.max() ?? 0) - (subviews.isEmpty ? 0 : spacing))
    }
}
