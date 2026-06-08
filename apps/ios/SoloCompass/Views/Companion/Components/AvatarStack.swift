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

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var appeared = false

    private var overlap: CGFloat { size * 0.32 }

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

    private var a11yLabel: String {
        if ids.count == 1 {
            return NSLocalizedString("avatarstack.one", comment: "")
        } else {
            return String(format: NSLocalizedString("avatarstack.count", comment: ""), ids.count)
        }
    }

    public var body: some View {
        HStack(spacing: -(overlap)) {
            ForEach(Array(visible.enumerated()), id: \.offset) { index, id in
                avatarCircle(color: UserDirectory.color(forId: id), index: index)
            }
            if overflow > 0 {
                overflowBubble
                    .opacity(appeared ? 1 : 0)
                    .scaleEffect(appeared ? 1 : 0.6)
                    .animation(
                        reduceMotion ? nil : .spring(response: 0.4, dampingFraction: 0.7)
                            .delay(Double(visible.count) * 0.05),
                        value: appeared
                    )
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(a11yLabel)
        .onAppear {
            if reduceMotion {
                appeared = true
            } else {
                withAnimation(.easeOut(duration: 0.35)) {
                    appeared = true
                }
            }
        }
    }

    // MARK: - Private Views

    @ViewBuilder
    private func avatarCircle(color: Color, index: Int) -> some View {
        Circle()
            .fill(color)
            .frame(width: size, height: size)
            .overlay(
                Circle()
                    .strokeBorder(ring, lineWidth: 1.5)
            )
            .opacity(appeared ? 1 : 0)
            .scaleEffect(appeared ? 1 : 0.6)
            .animation(
                reduceMotion ? nil : .spring(response: 0.4, dampingFraction: 0.7)
                    .delay(Double(index) * 0.05),
                value: appeared
            )
    }

    private var overflowBubble: some View {
        ZStack {
            Circle()
                .fill(CT.surfaceSunken)
                .frame(width: size, height: size)
                .overlay(
                    Circle()
                        .strokeBorder(ring, lineWidth: 1.5)
                )
            Text("+\(overflow)")
                .font(.system(size: size * 0.38, weight: .semibold))
                .foregroundStyle(CT.fgMuted)
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
