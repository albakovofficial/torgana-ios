import SwiftUI

// Плашки в несколько строк.
struct FlowLayout: Layout {
    var spacing: CGFloat = 8
    var center = false

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, row: CGFloat = 0, maxX: CGFloat = 0
        for v in subviews {
            let s = v.sizeThatFits(.unspecified)
            if x > 0 && x + s.width > width { x = 0; y += row + spacing; row = 0 }
            x += s.width + spacing
            row = max(row, s.height)
            maxX = max(maxX, x - spacing)
        }
        return CGSize(width: min(maxX, width), height: y + row)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        // Раскладываем по строкам; center — строки по центру (плашки категорий на экране входа).
        var rows: [[(LayoutSubview, CGSize)]] = [[]]
        var x: CGFloat = 0
        for v in subviews {
            let s = v.sizeThatFits(.unspecified)
            if x > 0 && x + s.width > bounds.width { rows.append([]); x = 0 }
            rows[rows.count - 1].append((v, s))
            x += s.width + spacing
        }
        var y = bounds.minY
        for r in rows {
            let w = r.map(\.1.width).reduce(0, +) + spacing * CGFloat(max(r.count - 1, 0))
            var x = bounds.minX + (center ? (bounds.width - w) / 2 : 0)
            for (v, s) in r { v.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(s)); x += s.width + spacing }
            y += (r.map(\.1.height).max() ?? 0) + spacing
        }
    }
}
