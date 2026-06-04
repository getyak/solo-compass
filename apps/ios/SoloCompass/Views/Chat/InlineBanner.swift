import SwiftUI

/// Unified inline banner for the chat surface. Replaces the five ad-hoc
/// `HStack + material` banners that used to live in `ChatSheet` / `ChatInputBar`
/// (error, unconfigured, send-hint, permission-denied, voice-interruption) with
/// one consistent card: a 3pt tone-colored left rail, an icon, title/subtitle
/// text, and optional CTA / dismiss affordances.
///
/// Tone drives the rail + icon color and the default SF Symbol. Callers supply
/// the localized copy and any actions; everything is optional past `title`.
@MainActor
public struct InlineBanner: View {
    public enum Tone {
        case error
        case warning
        case permission
        case info

        var railColor: Color {
            switch self {
            case .error:      return CT.bannerError
            case .warning:    return CT.toneForming
            case .permission: return CT.sunGoldDeep
            case .info:       return CT.fgSubtle
            }
        }

        var icon: String {
            switch self {
            case .error:      return "exclamationmark.triangle.fill"
            case .warning:    return "exclamationmark.circle.fill"
            case .permission: return "lock.fill"
            case .info:       return "info.circle.fill"
            }
        }
    }

    private let tone: Tone
    private let title: String
    private let subtitle: String?
    private let icon: String?
    private let ctaLabel: String?
    private let onCTA: (() -> Void)?
    private let onDismiss: (() -> Void)?

    @Environment(\.colorScheme) private var colorScheme

    public init(
        tone: Tone,
        title: String,
        subtitle: String? = nil,
        icon: String? = nil,
        ctaLabel: String? = nil,
        onCTA: (() -> Void)? = nil,
        onDismiss: (() -> Void)? = nil
    ) {
        self.tone = tone
        self.title = title
        self.subtitle = subtitle
        self.icon = icon
        self.ctaLabel = ctaLabel
        self.onCTA = onCTA
        self.onDismiss = onDismiss
    }

    public var body: some View {
        HStack(spacing: 0) {
            Rectangle()
                .fill(tone.railColor)
                .frame(width: 3)

            HStack(alignment: .top, spacing: 10) {
                Image(systemName: icon ?? tone.icon)
                    .font(.callout)
                    .foregroundStyle(tone.railColor)
                    .padding(.top, 1)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.primary)
                        .fixedSize(horizontal: false, vertical: true)
                    if let subtitle, !subtitle.isEmpty {
                        Text(subtitle)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                Spacer(minLength: 4)

                if let ctaLabel, let onCTA {
                    Button(action: onCTA) {
                        Text(ctaLabel)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(CT.accent)
                    }
                    .buttonStyle(.plain)
                }

                if let onDismiss {
                    Button(action: onDismiss) {
                        Image(systemName: "xmark")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .frame(width: 24, height: 24)
                            .background(surfaceFill, in: Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text(NSLocalizedString("common.dismiss", comment: "Dismiss")))
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
        }
        .background(surfaceFill)
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(borderColor, lineWidth: 0.5)
        )
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .shadow(color: .black.opacity(0.04), radius: 2, y: 1)
        .accessibilityElement(children: .combine)
        .transition(.move(edge: .top).combined(with: .opacity))
    }

    /// Dark mode keeps the warm sunken tint off so the banner stays legible on
    /// a near-black background; light mode uses the parchment surface token.
    private var surfaceFill: Color {
        colorScheme == .dark ? Color(.secondarySystemBackground) : CT.surfaceSunken
    }

    private var borderColor: Color {
        colorScheme == .dark ? Color(.separator) : CT.borderDefault
    }
}

#Preview("Tones") {
    VStack(spacing: 10) {
        InlineBanner(
            tone: .error,
            title: "Connection interrupted",
            subtitle: "Please try again in a moment.",
            ctaLabel: "Retry",
            onCTA: {}
        )
        InlineBanner(
            tone: .permission,
            title: "Microphone access needed",
            subtitle: "Enable it in Settings to talk.",
            ctaLabel: "Settings",
            onCTA: {}
        )
        InlineBanner(
            tone: .info,
            title: "Waking up the agent…",
            subtitle: "Give it a second, then send again."
        )
        InlineBanner(
            tone: .warning,
            title: "Recording was interrupted",
            onDismiss: {}
        )
    }
    .padding()
    .background(CT.bgWarm)
}
