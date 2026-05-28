import SwiftUI

// MARK: - Constants

private let peekHeight: CGFloat = 170
private let midHeight: CGFloat = 500
private let fullHeight: CGFloat = 800
private let minHeight: CGFloat = 120
private let maxHeight: CGFloat = 830
private let cornerRadius: CGFloat = 20
private let scrimMaxOpacity: CGFloat = 0.18

// MARK: - Detent

enum BottomSheetDetent {
    case peek, mid, full

    var height: CGFloat {
        switch self {
        case .peek: return peekHeight
        case .mid: return midHeight
        case .full: return fullHeight
        }
    }

    static func nearest(to height: CGFloat) -> BottomSheetDetent {
        let all: [BottomSheetDetent] = [.peek, .mid, .full]
        return all.min(by: { abs($0.height - height) < abs($1.height - height) }) ?? .peek
    }
}

// MARK: - BottomInfoSheet

public struct BottomInfoSheet<Content: View>: View {
    @State private var currentDetent: BottomSheetDetent = .peek
    @State private var dragOffset: CGFloat = 0
    @State private var isDragging: Bool = false

    private let aiHint: String
    private let count: Int
    private let isNowMode: Bool
    private let content: Content

    public init(
        aiHint: String,
        count: Int,
        isNowMode: Bool,
        @ViewBuilder content: () -> Content
    ) {
        self.aiHint = aiHint
        self.count = count
        self.isNowMode = isNowMode
        self.content = content()
    }

    private var baseHeight: CGFloat { currentDetent.height }

    private var displayHeight: CGFloat {
        let h = baseHeight - dragOffset
        return max(minHeight, min(maxHeight, h))
    }

    private var scrimOpacity: CGFloat {
        let fraction = (displayHeight - peekHeight) / (fullHeight - peekHeight)
        return max(0, min(1, fraction)) * scrimMaxOpacity
    }

    public var body: some View {
        ZStack(alignment: .bottom) {
            // Map scrim overlay
            Color.black
                .opacity(scrimOpacity)
                .ignoresSafeArea()
                .allowsHitTesting(false)

            // Sheet
            VStack(spacing: 0) {
                dragHandleArea
                NowHintRow(hint: aiHint)
                    .padding(.horizontal, 16)
                    .padding(.top, 6)
                SortCountToolbar(count: count, isNowMode: isNowMode)
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                content
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity)
            .frame(height: displayHeight)
            .background(
                UnevenRoundedRectangle(
                    topLeadingRadius: cornerRadius,
                    bottomLeadingRadius: 0,
                    bottomTrailingRadius: 0,
                    topTrailingRadius: cornerRadius
                )
                .fill(.ultraThinMaterial)
            )
        }
        .animation(isDragging ? nil : .spring(response: 0.3, dampingFraction: 0.85), value: displayHeight)
    }

    // MARK: - Drag Handle

    private var dragHandleArea: some View {
        // 24×16 pt hit area containing a 36×4 pill
        ZStack {
            Color.clear
                .frame(width: 24, height: 16)
                .contentShape(Rectangle())

            Capsule()
                .fill(Color.secondary.opacity(0.5))
                .frame(width: 36, height: 4)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 8)
        .gesture(
            DragGesture(minimumDistance: 4)
                .onChanged { value in
                    isDragging = true
                    dragOffset = value.translation.height
                }
                .onEnded { value in
                    isDragging = false
                    let projectedHeight = baseHeight - value.predictedEndTranslation.height
                    let clampedHeight = max(minHeight, min(maxHeight, projectedHeight))
                    currentDetent = BottomSheetDetent.nearest(to: clampedHeight)
                    dragOffset = 0
                }
        )
    }
}

// MARK: - NowHintRow

struct NowHintRow: View {
    let hint: String

    private var timeString: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: Date())
    }

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "sunset.fill")
                .font(.caption)
                .foregroundStyle(.orange)
            Text(hint)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Spacer(minLength: 4)
            Text(timeString)
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text("\(hint) \(timeString)"))
    }
}

// MARK: - SortCountToolbar

struct SortCountToolbar: View {
    let count: Int
    let isNowMode: Bool

    var body: some View {
        HStack {
            sortButton
            Spacer()
            countBadge
        }
    }

    private var sortButton: some View {
        Button {
            // Sort dropdown — behavior added in a follow-up story
        } label: {
            HStack(spacing: 4) {
                Text(NSLocalizedString("sheet.sort.button", comment: "Sort"))
                    .font(.caption.weight(.medium))
                Image(systemName: "chevron.down")
                    .font(.caption2.weight(.semibold))
            }
            .foregroundStyle(.primary)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Capsule().fill(.regularMaterial))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(NSLocalizedString("sheet.sort.button", comment: "Sort")))
    }

    private var countBadge: some View {
        let key = isNowMode ? "sheet.count.now" : "sheet.count.nearby"
        let label = String(
            format: NSLocalizedString(key, comment: "Count badge"),
            count
        )
        return Text(label)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Capsule().fill(Color.secondary.opacity(0.12)))
            .accessibilityLabel(Text(label))
    }
}

// MARK: - Preview

#Preview {
    ZStack(alignment: .bottom) {
        Color.teal.ignoresSafeArea()

        BottomInfoSheet(
            aiHint: NSLocalizedString("ai.now.hint", comment: "AI now hint"),
            count: 7,
            isNowMode: false
        ) {
            VStack(alignment: .leading, spacing: 12) {
                Text("Nearby Places")
                    .font(.headline)
                    .padding(.horizontal)
                ForEach(0..<5) { i in
                    Text("Place \(i + 1)")
                        .padding(.horizontal)
                }
            }
            .padding(.top, 8)
        }
    }
}
