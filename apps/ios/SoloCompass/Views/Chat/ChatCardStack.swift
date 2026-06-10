import SwiftUI

/// Renders the inline cards a single assistant turn produced, directly beneath
/// its bubble. Place cards lay out as a horizontally scrolling rail (a row of
/// suggestions reads as "here are a few options"); a proposed route renders as
/// one full-width card. Tapping a card is the user's explicit action — see
/// `ChatExperienceCard` / `ChatRouteProposalCard`.
@MainActor
struct ChatCardStack: View {
    let cards: [ChatCard]
    let onSelectExperience: (Experience) -> Void
    let onAdoptRoute: (RouteProposal) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(cards) { card in
                switch card {
                case let .experiences(_, list):
                    experienceRail(list)
                case let .route(_, proposal):
                    ChatRouteProposalCard(
                        proposal: proposal,
                        onAdopt: { onAdoptRoute(proposal) },
                        onTapStop: onSelectExperience
                    )
                }
            }
        }
        // Align under the assistant avatar (32 + 8 spacing) so cards sit in the
        // assistant's column, not full-bleed.
        .padding(.leading, 40)
        .padding(.trailing, 8)
        .transition(.opacity.combined(with: .move(edge: .bottom)))
    }

    @ViewBuilder
    private func experienceRail(_ list: [Experience]) -> some View {
        if list.count == 1, let only = list.first {
            ChatExperienceCard(experience: only) { onSelectExperience(only) }
        } else {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(list) { exp in
                        ChatExperienceCard(experience: exp) { onSelectExperience(exp) }
                    }
                }
                .padding(.vertical, 2)
            }
        }
    }
}

/// Elegant, ordered "thinking" trace shown while the agent works. Each step is a
/// pill with a kind-specific icon (deliberate / tool running / derived insight)
/// so the user can watch the agent reason about weather, location, and what
/// they've visited — instead of staring at an opaque spinner. Collapses to the
/// most recent few steps so it never dominates the thread.
@MainActor
struct ReasoningTracePanel: View {
    let steps: [ReasoningStep]

    /// Show at most this many trailing steps so a long tool chain doesn't push
    /// the conversation off-screen.
    private static let maxVisible = 4

    @Environment(\.colorScheme) private var colorScheme

    private var visibleSteps: [ReasoningStep] {
        Array(steps.suffix(Self.maxVisible))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "brain")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(CT.sunGoldDeep)
                Text(NSLocalizedString("chat.thinking.title", comment: "Reasoning trace panel title — Thinking it through"))
                    .font(.caption2.weight(.semibold))
                    .textCase(.uppercase)
                    .tracking(0.6)
                    .foregroundStyle(CT.sunGoldDeep)
            }
            ForEach(visibleSteps) { step in
                HStack(alignment: .firstTextBaseline, spacing: 7) {
                    Image(systemName: icon(for: step.kind))
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(tint(for: step.kind))
                        .frame(width: 14)
                    Text(step.label)
                        .font(.caption2)
                        // Semantic color: CT.fgMuted is a fixed dark brown and
                        // dropped below ~2.5:1 contrast on the dark-mode panel fill.
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                }
                .transition(.opacity)
            }
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(panelFill)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(CT.borderSubtle, lineWidth: 0.5)
        )
        .padding(.leading, 40)
        .padding(.trailing, 8)
        .animation(.easeInOut(duration: 0.2), value: steps.count)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text(
            NSLocalizedString("chat.thinking.a11y", comment: "Reasoning trace accessibility prefix")
                + ": " + visibleSteps.map(\.label).joined(separator: ", ")
        ))
    }

    private func icon(for kind: ReasoningStep.Kind) -> String {
        switch kind {
        case .thinking: return "ellipsis"
        case .tool:     return "gearshape.fill"
        case .insight:  return "lightbulb.fill"
        }
    }

    private func tint(for kind: ReasoningStep.Kind) -> Color {
        switch kind {
        case .thinking: return CT.fgSubtle
        case .tool:     return CT.accent
        case .insight:  return CT.sunGoldDeep
        }
    }

    private var panelFill: Color {
        colorScheme == .dark ? Color(.secondarySystemBackground) : CT.sunGoldSoft.opacity(0.35)
    }
}

/// The single, quiet status line shown while the agent is working.
///
/// Replaces the old pairing of an always-on `ReasoningTracePanel` *and* a
/// `TypingIndicatorBubble` — two competing loaders on screen at once. Here there
/// is exactly one: a small spinner plus one cycling phrase (the orchestrator's
/// current `thinkingStep`), the phrase cross-fading as the step changes. When the
/// turn finishes this line disappears and its reasoning collapses into a
/// `ReasoningSummaryChip` pinned under the reply.
@MainActor
struct AgentStatusLine: View {
    /// The current localized step label (e.g. "🔍 Searching nearby…"). Falls back
    /// to a neutral "Working…" when the orchestrator hasn't named a step yet.
    let label: String

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var spinning = false

    private var phrase: String {
        label.isEmpty
            ? NSLocalizedString("chat.thinking.working", comment: "Neutral agent working status")
            : label
    }

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .trim(from: 0.12, to: 0.92)
                .stroke(CT.accent, style: StrokeStyle(lineWidth: 1.6, lineCap: .round))
                .frame(width: 13, height: 13)
                .rotationEffect(.degrees(spinning ? 360 : 0))
                .animation(
                    reduceMotion ? nil : .linear(duration: 0.9).repeatForever(autoreverses: false),
                    value: spinning
                )
                .onAppear { spinning = true }

            // Keying on the phrase makes SwiftUI treat each new step as a fresh
            // view, so the label cross-fades instead of hard-cutting.
            Text(phrase)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .id(phrase)
                .transition(.opacity)
                .animation(.easeOut(duration: 0.25), value: phrase)
        }
        .padding(.vertical, 6)
        .padding(.leading, 40)
        .padding(.trailing, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .transition(.opacity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(phrase))
        .accessibilityAddTraits(.updatesFrequently)
    }
}

/// The collapsed, tappable record of a finished turn's reasoning, pinned under
/// the assistant bubble. Reads like a result ("✓ Searched 14 places · 2 matched")
/// and expands to the full ordered step detail on tap — keeping the calm of a
/// single status line in the moment while staying fully auditable afterward.
@MainActor
struct ReasoningSummaryChip: View {
    let summary: ReasoningSummary

    @State private var expanded = false
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Button {
                guard summary.hasDetail else { return }
                Haptics.impact(.light)
                withAnimation(.easeInOut(duration: 0.22)) { expanded.toggle() }
            } label: {
                HStack(spacing: 7) {
                    Image(systemName: "checkmark")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(CT.verifiedGreen)
                        .frame(width: 16, height: 16)
                        .background(CT.verifiedGreen.opacity(0.14), in: Circle())
                    Text(summary.summary)
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    if summary.hasDetail {
                        Image(systemName: expanded ? "chevron.up" : "chevron.down")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(CT.fgSubtle)
                    }
                }
                .padding(.vertical, 5)
                .padding(.leading, 7)
                .padding(.trailing, summary.hasDetail ? 10 : 12)
                .background(chipFill, in: Capsule())
            }
            .buttonStyle(.plain)
            .disabled(!summary.hasDetail)

            if expanded {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(Array(summary.detail.enumerated()), id: \.offset) { _, line in
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Circle()
                                .fill(CT.borderDefault)
                                .frame(width: 5, height: 5)
                            Text(line)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                            Spacer(minLength: 0)
                        }
                    }
                }
                .padding(.leading, 8)
                .overlay(alignment: .leading) {
                    Rectangle()
                        .fill(CT.borderSubtle)
                        .frame(width: 1.5)
                }
                .padding(.leading, 4)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.leading, 40)
        .padding(.trailing, 8)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text(String(
            format: NSLocalizedString("chat.thinking.summary.a11y", comment: "Collapsed reasoning summary a11y"),
            summary.summary
        )))
    }

    private var chipFill: Color {
        colorScheme == .dark ? Color(.secondarySystemBackground) : CT.surfaceSunken
    }
}

#Preview("Reasoning — live + collapsed") {
    VStack(alignment: .leading, spacing: 18) {
        AgentStatusLine(label: "🔍 Searching nearby…")
        ReasoningSummaryChip(summary: ReasoningSummary(
            summary: "Searched 14 places · 2 matched",
            detail: [
                "Searched places — 14 within walking range",
                "Filtered: quiet, laptop-friendly — 2 matched",
                "Checked hours — both open now",
            ]
        ))
        ReasoningSummaryChip(summary: ReasoningSummary(
            summary: "Thought it through",
            detail: []
        ))
    }
    .padding()
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(CT.bgWarm)
}
