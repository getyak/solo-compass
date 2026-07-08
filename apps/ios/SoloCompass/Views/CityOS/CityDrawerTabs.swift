import SwiftUI

/// City OS v2 · the two glass drawer tabs floating just above the peek sheet in
/// Live mode (PRD §5.2–5.3): 「落地包」and 「在地 · 本周」. They are the way
/// back into the kit sheet (which only auto-surfaces once) and the live-events
/// sheet. Shown only at the peek detent, in Live mode, with no card selected —
/// so they never compete with the Now card or an active selection.
struct CityDrawerTabs: View {
    let kitCount: Int
    let eventCount: Int
    let onOpenKit: () -> Void
    let onOpenLive: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(spacing: 10) {
            tab(
                title: NSLocalizedString("cityos.tab.kit", comment: "落地包"),
                symbol: "shippingbox.fill",
                count: nil,
                action: onOpenKit
            )
            tab(
                title: NSLocalizedString("cityos.tab.live", comment: "在地 · 本周"),
                symbol: "calendar",
                count: eventCount > 0 ? eventCount : nil,
                action: onOpenLive
            )
        }
    }

    private var pillBg: Color {
        colorScheme == .dark ? CT.warmCardDark : CT.surfaceWhite
    }

    private func tab(title: String, symbol: String, count: Int?, action: @escaping () -> Void) -> some View {
        Button {
            Haptics.impact(.light)
            action()
        } label: {
            HStack(spacing: 7) {
                Image(systemName: symbol)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(CT.accent)
                Text(title)
                    .font(CT.body(13, .semibold))
                if let count {
                    Text("\(count)")
                        .font(CT.mono(11, .semibold))
                        .foregroundStyle(CT.accent)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 1)
                        .background(Capsule().fill(CT.accentSoft))
                }
            }
            .foregroundStyle(colorScheme == .dark ? CT.fgPrimaryDark : CT.fgPrimary)
            .padding(.leading, 14)
            .padding(.trailing, count == nil ? 14 : 10)
            .padding(.vertical, 10)
            .background(
                Capsule()
                    .fill(pillBg)
                    .overlay(Capsule().strokeBorder(
                        colorScheme == .dark ? CT.warmBorderDark : CT.borderSubtle,
                        lineWidth: 0.5
                    ))
            )
            .shadow(color: CT.scrimShadow, radius: 8, y: 3)
        }
        .buttonStyle(PressableButtonStyle(pressedScale: 0.96))
        .accessibilityLabel(Text(count.map { "\(title), \($0)" } ?? title))
    }
}
