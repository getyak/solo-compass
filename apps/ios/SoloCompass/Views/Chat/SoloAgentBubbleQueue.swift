import SwiftUI

/// A single speech-bubble the Solo mascot pushes toward the traveler from the
/// bottom-right FAB. Bubbles are enqueued by the startup self-diagnostics flow
/// (see `StartupDiagnosticsService`) and by any future proactive nudge that
/// wants an in-app affordance instead of a system notification.
public struct SoloAgentBubble: Identifiable, Equatable, Sendable {

    public enum Tone: Sendable, Equatable {
        case info
        case warn
        case error

        var badge: String {
            switch self {
            case .info: return "info.circle.fill"
            case .warn: return "exclamationmark.triangle.fill"
            case .error: return "xmark.octagon.fill"
            }
        }
    }

    public let id: UUID
    public let tone: Tone
    public let title: String
    public let subtitle: String?
    /// Optional CTA — when non-nil, the bubble stays until the traveler taps
    /// (or dismisses). When nil, the bubble auto-dismisses after
    /// `autoDismissAfter` seconds.
    public let ctaLabel: String?
    public let autoDismissAfter: TimeInterval

    public init(
        id: UUID = UUID(),
        tone: Tone,
        title: String,
        subtitle: String? = nil,
        ctaLabel: String? = nil,
        autoDismissAfter: TimeInterval = 6
    ) {
        self.id = id
        self.tone = tone
        self.title = title
        self.subtitle = subtitle
        self.ctaLabel = ctaLabel
        self.autoDismissAfter = autoDismissAfter
    }
}

/// FIFO queue holding at most one visible bubble at a time. `enqueue()` appends;
/// the head is what the view shows. `dismiss(id:)` pops the head only if the id
/// matches — this prevents a stale auto-dismiss timer from removing a bubble
/// the user has already replaced.
@Observable
@MainActor
public final class SoloAgentBubbleQueue {
    public private(set) var items: [SoloAgentBubble] = []

    public init() {}

    public var head: SoloAgentBubble? { items.first }

    public func enqueue(_ bubble: SoloAgentBubble) {
        guard !items.contains(where: { $0.id == bubble.id }) else { return }
        items.append(bubble)
    }

    public func dismiss(id: UUID) {
        items.removeAll { $0.id == id }
    }

    public func clear() {
        items.removeAll()
    }
}

// MARK: - View

/// Renders the queue's head bubble to the *left* of the Solo mascot FAB with a
/// tail pointing bottom-right. Parent view is responsible for positioning the
/// overlay so the tail lines up with the mascot.
public struct SoloAgentBubbleView: View {
    @Bindable var queue: SoloAgentBubbleQueue
    let onTapCTA: (SoloAgentBubble) -> Void

    public init(queue: SoloAgentBubbleQueue, onTapCTA: @escaping (SoloAgentBubble) -> Void) {
        self.queue = queue
        self.onTapCTA = onTapCTA
    }

    public var body: some View {
        Group {
            if let bubble = queue.head {
                bubbleBody(for: bubble)
                    .transition(.asymmetric(
                        insertion: .move(edge: .top).combined(with: .opacity),
                        removal: .move(edge: .top).combined(with: .opacity)
                    ))
                    .task(id: bubble.id) {
                        guard bubble.ctaLabel == nil else { return }
                        try? await Task.sleep(nanoseconds: UInt64(bubble.autoDismissAfter * 1_000_000_000))
                        if queue.head?.id == bubble.id {
                            withAnimation(.easeOut(duration: 0.2)) {
                                queue.dismiss(id: bubble.id)
                            }
                        }
                    }
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: queue.head?.id)
    }

    @ViewBuilder
    private func bubbleBody(for bubble: SoloAgentBubble) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: bubble.tone.badge)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(toneColor(bubble.tone))
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 4) {
                Text(bubble.title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(CT.fgPrimary)
                    .fixedSize(horizontal: false, vertical: true)

                if let subtitle = bubble.subtitle {
                    Text(subtitle)
                        .font(.system(size: 12))
                        .foregroundStyle(CT.fgPrimary.opacity(0.7))
                        .lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if let cta = bubble.ctaLabel {
                    Button {
                        onTapCTA(bubble)
                    } label: {
                        Text(cta)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(CT.surfaceWhite)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .fill(CT.accent)
                            )
                    }
                    // `.borderedProminent` would double-fill; we want the
                    // brown background above and Apple's default press
                    // treatment (scale-down + opacity dim) on top of it —
                    // that's exactly what `.plain` misses.
                    .buttonStyle(BubbleCTAButtonStyle())
                    .padding(.top, 6)
                    .accessibilityIdentifier("solo.agent.bubble.cta")
                }
            }

            if bubble.ctaLabel != nil {
                Button {
                    withAnimation(.easeOut(duration: 0.2)) {
                        queue.dismiss(id: bubble.id)
                    }
                } label: {
                    // 32×32 tap target inside a 20pt visual — matches Apple
                    // HIG's ≥44pt combined-target for close chips while
                    // keeping the visual glyph small so it doesn't compete
                    // with the CTA. `.contentShape` extends the hit area
                    // beyond the icon's tight bounds.
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(CT.fgPrimary.opacity(0.28))
                        .frame(width: 32, height: 32)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text(NSLocalizedString(
                    "solo.agent.bubble.dismiss",
                    value: "关掉",
                    comment: "Dismiss the Solo Agent bubble"
                )))
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: 260, alignment: .leading)
        .background(bubbleShape)
        .shadow(color: .black.opacity(0.14), radius: 10, y: 4)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("solo.agent.bubble")
    }

    private var bubbleShape: some View {
        RoundedRectangle(cornerRadius: 14, style: .continuous)
            .fill(CT.surfaceWhite)
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(CT.accentBorder, lineWidth: 1)
            )
    }

    private func toneColor(_ tone: SoloAgentBubble.Tone) -> Color {
        switch tone {
        case .info: return CT.accent
        case .warn: return Color(red: 0.85, green: 0.55, blue: 0.10)
        case .error: return Color(red: 0.78, green: 0.20, blue: 0.15)
        }
    }
}

/// Scale-and-dim press treatment for the bubble CTA. Kept private to this
/// file so it doesn't compete with the FAB / filter styles used elsewhere.
private struct BubbleCTAButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1.0)
            .opacity(configuration.isPressed ? 0.85 : 1.0)
            .animation(.spring(response: 0.18, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

