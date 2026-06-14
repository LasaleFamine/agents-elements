import SwiftUI

/// Wrapping flow layout for chips/pills (left-aligned, wraps to available width).
struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        let rows = layout(subviews: subviews, maxWidth: maxWidth)
        let height = rows.last.map { $0.y + $0.height } ?? 0
        return CGSize(width: proposal.width ?? rows.map { $0.maxX }.max() ?? 0, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) {
        let rows = layout(subviews: subviews, maxWidth: bounds.width)
        for row in rows {
            for item in row.items {
                let size = subviews[item.index].sizeThatFits(.unspecified)
                subviews[item.index].place(
                    at: CGPoint(x: bounds.minX + item.x, y: bounds.minY + row.y),
                    proposal: ProposedViewSize(size)
                )
            }
        }
    }

    private struct Item { let index: Int; let x: CGFloat }
    private struct Row { var items: [Item] = []; var y: CGFloat = 0; var height: CGFloat = 0; var maxX: CGFloat = 0 }

    private func layout(subviews: Subviews, maxWidth: CGFloat) -> [Row] {
        var rows: [Row] = []
        var current = Row()
        var x: CGFloat = 0
        var y: CGFloat = 0
        for (i, sub) in subviews.enumerated() {
            let size = sub.sizeThatFits(.unspecified)
            if x + size.width > maxWidth, !current.items.isEmpty {
                current.y = y
                rows.append(current)
                y += current.height + spacing
                current = Row()
                x = 0
            }
            current.items.append(Item(index: i, x: x))
            current.height = max(current.height, size.height)
            x += size.width + spacing
            current.maxX = max(current.maxX, x)
        }
        if !current.items.isEmpty { current.y = y; rows.append(current) }
        return rows
    }
}
