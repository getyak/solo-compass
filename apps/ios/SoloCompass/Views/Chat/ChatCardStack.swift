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
                        .foregroundStyle(CT.fgMuted)
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
