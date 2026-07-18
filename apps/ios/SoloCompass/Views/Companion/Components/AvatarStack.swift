import SwiftUI

// MARK: - VerifiedStyle
/// Controls how a "verified" badge is rendered depending on context.
public enum VerifiedStyle {
    case badge   // small checkmark overlay on avatar
    case header  // full badge row at the top of a card/sheet
    case inline  // compact text-level indicator beside a name
}

// MARK: - AvatarStack

/// Horizontally overlapping avatar circles, one per unique user id.
///
/// Duplicate ids are collapsed to first-seen order before rendering.
/// When `uniqueIds.count > maxVisible` a "+N" overflow bubble is appended;
/// tapping it opens a popover listing every unique member by name + color.
public struct AvatarStack: View {
    let ids: [String]
    var maxVisible: Int = 5
    var size: CGFloat = 24
    var ring: Color = .white

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var appeared = false
    @State private var showAll = false

    private var overlap: CGFloat { size * 0.32 }

    // De-duplicate while preserving first-seen order.
    private var uniqueIds: [String] {
        var seen = Set<String>()
        return ids.filter { seen.insert($0).inserted }
    }

    private var visible: [String] {
        Array(uniqueIds.prefix(maxVisible))
    }

    private var overflow: Int {
        max(0, uniqueIds.count - maxVisible)
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
        if uniqueIds.count == 1 {
            return NSLocalizedString("avatarstack.one", comment: "")
        } else {
            return String(format: NSLocalizedString("avatarstack.count", comment: ""), uniqueIds.count)
        }
    }

    public var body: some View {
        HStack(spacing: -(overlap)) {
            ForEach(Array(visible.enumerated()), id: \.offset) { index, id in
                avatarCircle(color: UserDirectory.color(forId: id), index: index)
            }
            if overflow > 0 {
                overflowButton
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

    // A real Button, not a `.simultaneousGesture(DragGesture(minimumDistance:0))`
    // acting as the tap. This component is embedded inside RouteCard, which
    // lives in the BottomInfoSheet's ScrollView; a zero-distance drag there
    // claims the touch the instant a finger lands, so the host scroll view
    // classifies the release as a drag and the "show all" popover either
    // misfires while scrolling or swallows the scroll. A Button + ButtonStyle
    // lets the tap reach the action and the scroll pass through — the same fix
    // already applied to RouteCard / CreateRouteView. See [[project_dead_fab_sheet_wiring]].
    private var overflowButton: some View {
        Button {
            Haptics.selection()
            showAll = true
        } label: {
            overflowBubble
        }
        .buttonStyle(PressableButtonStyle(pressedScale: 0.94, haptic: false))
        .accessibilityHint(NSLocalizedString("avatarstack.overflow.hint", comment: ""))
        .popover(isPresented: $showAll) {
            membersPopover
                .presentationCompactAdaptation(.popover)
        }
    }

    private var membersPopover: some View {
        NavigationView {
            List(uniqueIds, id: \.self) { id in
                HStack(spacing: 10) {
                    Circle()
                        .fill(UserDirectory.color(forId: id))
                        .frame(width: 20, height: 20)
                        .overlay(Circle().strokeBorder(Color(.systemBackground), lineWidth: 1))
                    Text(UserDirectory.displayName(forId: id))
                        .font(.body)
                }
            }
            .listStyle(.plain)
            .navigationTitle(NSLocalizedString("avatarstack.members.title", comment: ""))
            .navigationBarTitleDisplayMode(.inline)
        }
        .frame(minWidth: 220, minHeight: CGFloat(min(uniqueIds.count, 8)) * 52 + 60)
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

#Preview("duplicates collapsed") {
    AvatarStack(ids: ["alice", "bob", "alice", "carol", "bob", "dave", "alice"])
        .padding()
        .background(Color(.systemBackground))
}
