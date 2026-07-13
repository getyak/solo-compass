import SwiftUI

/// City OS v2 · visa compliance banner (PRD §4.3). Surfaces at the top of the
/// map when the traveler's visa has ≤7 days left. Warm amber, mono day count,
/// a 「处理」 CTA that opens the kit sheet focused on the visa row, and a
/// dismiss X. Deliberately NO haptic on appear — it's information, not an alarm;
/// the interruption budget already gates how often it can show.
struct ComplianceBanner: View {
    let daysRemaining: Int
    /// Open the landing kit focused on the visa row.
    let onHandle: () -> Void
    /// Session-scoped dismiss (reappears next day per the interruption budget).
    let onDismiss: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "person.text.rectangle")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(CT.warningText)

            label

            Spacer(minLength: 8)

            Button(action: onHandle) {
                Text(NSLocalizedString("cityos.compliance.handle", comment: "处理"))
                    .ctBody(13, .semibold)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Capsule().fill(CT.accent))
            }
            .buttonStyle(PressableButtonStyle(pressedScale: 0.96))

            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(CT.fgMuted)
                    .frame(width: 28, height: 28)
            }
            .accessibilityLabel(Text(NSLocalizedString("common.dismiss", comment: "Dismiss")))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(CT.warningSoft)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(CT.warningText.opacity(0.2), lineWidth: 0.5)
        )
        .shadow(color: CT.scrimShadow, radius: 8, y: 2)
        .padding(.horizontal, 16)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text(a11yLabel))
    }

    /// "签证还剩 N 天" with the number in mono bold. Overstay (negative) reads
    /// as its own line so it never looks like a normal countdown.
    private var label: some View {
        Group {
            if daysRemaining < 0 {
                Text(String(
                    format: NSLocalizedString("cityos.compliance.overstay", comment: "已逾期 N 天"),
                    abs(daysRemaining)
                ))
                .ctBody(13, .semibold)
                .foregroundStyle(CT.warningText)
            } else {
                // Text(+)-concatenation requires each operand stay a `Text`, so
                // these keep the fixed-size CT.* Font factory — the `.ct*` view
                // modifiers return `some View` and can't be `+`-joined. Dynamic
                // Type is partially honored via `.minimumScaleFactor` below.
                (
                    Text(NSLocalizedString("cityos.compliance.prefix", comment: "签证还剩 "))
                        .font(CT.body(13, .medium))
                    + Text("\(daysRemaining)")
                        .font(CT.mono(15, .bold))
                    + Text(NSLocalizedString("cityos.compliance.suffix", comment: " 天"))
                        .font(CT.body(13, .medium))
                )
                .foregroundStyle(CT.warningText)
            }
        }
        .lineLimit(1)
        .minimumScaleFactor(0.8)
    }

    private var a11yLabel: String {
        if daysRemaining < 0 {
            return String(
                format: NSLocalizedString("cityos.compliance.overstay", comment: "已逾期 N 天"),
                abs(daysRemaining)
            )
        }
        return String(
            format: NSLocalizedString("cityos.compliance.a11y", comment: "Visa: N days remaining"),
            daysRemaining
        )
    }
}
