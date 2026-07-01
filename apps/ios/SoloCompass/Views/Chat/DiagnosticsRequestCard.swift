import SwiftUI

/// A compact "启动体检结果" card that replaces the raw user-turn text when
/// the traveler taps the startup-diagnostics banner. Same layer as
/// `ChatCardStack` — the message stays a `role: .user` turn (so the LLM
/// answers it) but its rendering skips `MessageBubble` and shows this
/// summary chip list instead.
public struct DiagnosticsRequestCard: View {

    public struct Finding: Identifiable, Equatable, Sendable {
        public let id = UUID()
        public let severity: String
        public let title: String
        public let suggestedFix: String

        public init(severity: String, title: String, suggestedFix: String) {
            self.severity = severity
            self.title = title
            self.suggestedFix = suggestedFix
        }
    }

    private let findings: [Finding]

    public init(findings: [Finding]) {
        self.findings = findings
    }

    public var body: some View {
        VStack(alignment: .trailing, spacing: 10) {
            // Header: monospaced small-caps caption — reads as a system
            // annotation, not a piece of chat. Space letters (tracking) so it
            // sits calmly next to the body face without shouting.
            HStack(spacing: 6) {
                Image(systemName: "stethoscope")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(CT.accent)
                Text(NSLocalizedString(
                    "diagnostics.card.header",
                    value: "启动体检结果",
                    comment: "Header on the diagnostics request card in chat"
                ))
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(CT.fgPrimary.opacity(0.55))
                .textCase(.uppercase)
                .tracking(1.2)
            }

            VStack(alignment: .leading, spacing: 10) {
                ForEach(Array(findings.enumerated()), id: \.element.id) { idx, finding in
                    findingRow(finding)
                    if idx < findings.count - 1 {
                        Divider()
                            .foregroundStyle(CT.accentBorder.opacity(0.6))
                            .padding(.leading, 24)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(CT.accentSoft)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(CT.accentBorder, lineWidth: 1)
            )

            // Human paraphrase in the body face. Right-aligned to signal this
            // is the traveler talking (like a chat bubble text) but chromeless
            // so the visual weight belongs to the summary card above.
            Text(NSLocalizedString(
                "diagnostics.card.ask",
                value: "帮我看看每条的影响,再告诉我怎么修。",
                comment: "One-line paraphrase of the diagnostics ask beneath the card"
            ))
            .font(.system(size: 14, weight: .regular))
            .lineSpacing(3)
            .foregroundStyle(CT.fgPrimary.opacity(0.75))
            .multilineTextAlignment(.trailing)
            .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("chat.diagnostics.card")
    }

    @ViewBuilder
    private func findingRow(_ f: Finding) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: iconName(f.severity))
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(iconColor(f.severity))
                .frame(width: 18, alignment: .center)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 3) {
                Text(f.title)
                    .font(.system(size: 15, weight: .semibold))
                    .lineSpacing(1)
                    .foregroundStyle(CT.fgPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                Text(f.suggestedFix)
                    .font(.system(size: 13, weight: .regular))
                    .lineSpacing(2)
                    .foregroundStyle(CT.fgPrimary.opacity(0.6))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func iconName(_ severity: String) -> String {
        switch severity.lowercased() {
        case "error": return "xmark.octagon.fill"
        case "warn":  return "exclamationmark.triangle.fill"
        default:      return "info.circle.fill"
        }
    }

    private func iconColor(_ severity: String) -> Color {
        switch severity.lowercased() {
        case "error": return Color(red: 0.78, green: 0.20, blue: 0.15)
        case "warn":  return Color(red: 0.85, green: 0.55, blue: 0.10)
        default:      return CT.accent
        }
    }
}
