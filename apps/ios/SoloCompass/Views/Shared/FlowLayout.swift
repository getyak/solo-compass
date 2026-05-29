import SwiftUI

/// A SwiftUI `Layout` that places subviews left-to-right, wrapping to a new
/// row when the next item would exceed the available width.
public struct FlowLayout: Layout {
    /// Horizontal and vertical spacing between items.
    var spacing: CGFloat

    public init(spacing: CGFloat = 8) {
        self.spacing = spacing
    }

    public func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = (proposal.width.flatMap { $0.isFinite ? $0 : nil }) ?? .greatestFiniteMagnitude
        var totalHeight: CGFloat = 0
        var rowWidth: CGFloat = 0
        var rowHeight: CGFloat = 0
        var isFirstInRow = true

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            let neededWidth = isFirstInRow ? size.width : rowWidth + spacing + size.width

            if !isFirstInRow && neededWidth > maxWidth {
                // Wrap: commit current row and start a new one.
                totalHeight += rowHeight + spacing
                rowWidth = size.width
                rowHeight = size.height
            } else {
                rowWidth = isFirstInRow ? size.width : rowWidth + spacing + size.width
                rowHeight = max(rowHeight, size.height)
                isFirstInRow = false
            }
        }
        // Commit the final row.
        totalHeight += rowHeight

        return CGSize(width: maxWidth == .greatestFiniteMagnitude ? rowWidth : maxWidth,
                      height: totalHeight)
    }

    public func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0
        var isFirstInRow = true

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)

            if !isFirstInRow && x + size.width > bounds.maxX {
                // Wrap to next row.
                y += rowHeight + spacing
                x = bounds.minX
                rowHeight = 0
            }

            subview.place(at: CGPoint(x: x, y: y), proposal: .unspecified)
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
            isFirstInRow = false
        }
    }
}

#Preview("FlowLayout wrapping") {
    FlowLayout(spacing: 8) {
        ForEach(["Short", "A bit longer", "Tiny", "Medium label", "Another", "Wrap me"], id: \.self) { text in
            Text(text)
                .font(.caption)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Capsule().fill(Color.secondary.opacity(0.15)))
        }
    }
    .padding()
    .frame(width: 200)
}
