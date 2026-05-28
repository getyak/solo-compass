import SwiftUI

// MARK: - VerifiedStyle

/// Controls how a "verified" badge is rendered depending on context.
public enum VerifiedStyle {
    case badge   // small checkmark overlay on avatar
    case header  // full badge row at the top of a card/sheet
    case inline  // compact text-level indicator beside a name
}

// MARK: - AvatarStack

/// Horizontally overlapping avatar circles, one per user id.
///
/// Each circle is filled with the user's deterministic color via
/// `UserDirectory.color(forId:)` and outlined with a white ring.
/// When `ids.count > maxVisible` a "+N" overflow bubble is appended.
public struct AvatarStack: View {
    let ids: [String]
    var maxVisible: Int = 5
    var size: CGFloat = 24
    var ring: Color = .white

    private let overlap: CGFloat = 6

    private var visible: [String] {
        Array(ids.prefix(maxVisible))
    }

    private var overflow: Int {
        max(0, ids.count - maxVisible)
    }

    public init(
        ids: [String],
        maxVisible: Int = 5,
        size: CGFloat = 24,
        ring: Color = .white
    ) {
        self.ids = ids
        self.maxVisible = maxVisible
        self.size = size
        self.ring = ring
    }

    public var body: some View {
        HStack(spacing: -(overlap)) {
            ForEach(Array(visible.enumerated()), id: \.offset) { _, id in
                avatarCircle(color: UserDirectory.color(forId: id))
            }
            if overflow > 0 {
                overflowBubble
            }
        }
    }

    // MARK: - Private Views

    @ViewBuilder
    private func avatarCircle(color: Color) -> some View {
        Circle()
            .fill(color)
            .frame(width: size, height: size)
            .overlay(
                Circle()
                    .strokeBorder(ring, lineWidth: 2)
            )
    }

    private var overflowBubble: some View {
        ZStack {
            Circle()
                .fill(Color(.systemGray4))
                .frame(width: size, height: size)
                .overlay(
                    Circle()
                        .strokeBorder(ring, lineWidth: 2)
                )
            Text("+\(overflow)")
                .font(.system(size: size * 0.38, weight: .semibold))
                .foregroundStyle(.primary)
        }
    }
}

// MARK: - Preview

#Preview("3 avatars") {
    AvatarStack(ids: ["alice", "bob", "carol"])
        .padding()
        .background(Color(.systemBackground))
}

#Preview("5 avatars") {
    AvatarStack(ids: ["alice", "bob", "carol", "dave", "eve"])
        .padding()
        .background(Color(.systemBackground))
}

#Preview("8 avatars (overflow)") {
    AvatarStack(ids: ["alice", "bob", "carol", "dave", "eve", "frank", "grace", "heidi"])
        .padding()
        .background(Color(.systemBackground))
}
