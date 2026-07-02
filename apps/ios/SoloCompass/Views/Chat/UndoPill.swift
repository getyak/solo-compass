import SwiftUI

/// ⑩ Card 可反悔性 — slice B: the small "撤回" pill overlaid on an inline
/// chat card while its ledger entry is still `.provisional`. Reads as the
/// countdown before the card commits ("撤回 · 2s"), and taps to pull the
/// card back through `onUndo`.
///
/// Timing is driven by `TimelineView(.animation)` so the label updates
/// every frame without a Timer allocation per card. When `deadline` has
/// passed, the pill folds away.
@MainActor
struct UndoPill: View {
    /// Wall-clock deadline at which the entry auto-commits. Cheap to feed
    /// per-card: SwiftUI diffs by value.
    let deadline: Date
    /// User tapped the pill → pull this card back. Slice B wires it to
    /// `orchestrator.undoCard(id:)`.
    let onUndo: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        // .animation ticks every display refresh; we recompute the label
        // each tick against `context.date`. TimelineView collapses to a
        // static render when the app backgrounds.
        TimelineView(.animation(minimumInterval: 0.1, paused: false)) { context in
            let remaining = max(0, deadline.timeIntervalSince(context.date))
            if remaining > 0 {
                Button(action: {
                    Haptics.impact(.light)
                    onUndo()
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.uturn.backward")
                            .font(.system(size: 10, weight: .semibold))
                        Text(String(
                            format: NSLocalizedString(
                                "chat.card.undo.pill",
                                comment: "Undo pill label — 撤回 · %ds"
                            ),
                            Int(ceil(remaining))
                        ))
                        .font(.caption2.weight(.semibold))
                        .monospacedDigit()
                    }
                    .foregroundStyle(CT.sunGoldDeep)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(CT.sunGoldSoft, in: Capsule())
                    .overlay(
                        Capsule()
                            .strokeBorder(CT.sunGoldDeep.opacity(0.25), lineWidth: 0.5)
                    )
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text(
                    NSLocalizedString(
                        "chat.card.undo.a11y",
                        comment: "Undo pill a11y — 撤回这张卡片,%d 秒后确认"
                    )
                    .replacingOccurrences(of: "%d", with: "\(Int(ceil(remaining)))")
                ))
                .accessibilityHint(Text(NSLocalizedString(
                    "chat.card.undo.a11y.hint",
                    comment: "Undo pill a11y hint — 双击撤回"
                )))
                .transition(reduceMotion ? .identity : .opacity)
            }
        }
    }
}

#Preview("UndoPill — 3s countdown") {
    UndoPill(
        deadline: Date().addingTimeInterval(3),
        onUndo: { print("undo tapped") }
    )
    .padding()
}
