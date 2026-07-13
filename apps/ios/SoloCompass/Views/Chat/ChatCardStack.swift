import SwiftUI

/// Renders the inline cards a single assistant turn produced, directly beneath
/// its bubble. Place results stack vertically as compact rows (each reads as a
/// "search result" line you can peek or open); a proposed route renders as one
/// full-width card. Tapping a card is the user's explicit action — see
/// `ChatExperienceCard` / `ChatRouteProposalCard`.
///
/// ⑩ Slice B: when `entries` is provided, each card gets a countdown
/// `UndoPill` overlay while its ledger entry is still `.provisional`. When
/// the caller doesn't pass `entries` (early-adopter tests, previews), the
/// stack falls back to the plain `cards` render — no pill, no swipe.
@MainActor
struct ChatCardStack: View {
    let cards: [ChatCard]
    let onSelectExperience: (Experience) -> Void
    let onAdoptRoute: (RouteProposal) -> Void
    /// City OS v2: user tapped "在地图上看" on an event card. nil (default) drops
    /// the affordance for callers that don't support map jumps.
    var onShowEventOnMap: ((CityEvent) -> Void)? = nil

    /// Slice B: parallel projection with per-card `.provisional/.committed`
    /// state so the pill can render its countdown. Must be aligned to
    /// `cards` — same order, same ids. When nil, no pill is drawn.
    var entries: [ProvisionalCardLedger.Entry]? = nil
    /// Slice B: called with the ledger entry id when the pill is tapped.
    /// Wired to `orchestrator.undoCard(id:)` at the ChatSheet layer.
    var onUndoCard: ((UUID) -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(cards.enumerated()), id: \.element.id) { index, card in
                cardRow(card: card, entry: entries?[safe: index])
            }
        }
        // Sit in the assistant's column but with room to breathe — compact
        // result rows want near-full width, matching the handoff `.ai-results`
        // block (max-width ~92%, left-aligned under the reply).
        .padding(.leading, 8)
        .padding(.trailing, 28)
        .transition(.opacity.combined(with: .move(edge: .bottom)))
    }

    @ViewBuilder
    private func cardRow(card: ChatCard, entry: ProvisionalCardLedger.Entry?) -> some View {
        let content = Group {
            switch card {
            case let .experiences(_, list):
                experienceResults(list)
            case let .route(_, proposal):
                ChatRouteProposalCard(
                    proposal: proposal,
                    onAdopt: { onAdoptRoute(proposal) },
                    onTapStop: onSelectExperience
                )
            case let .events(_, list):
                eventResults(list)
            }
        }
        // Slice B: overlay the undo pill only while the entry is
        // provisional. A committed / undone entry gets no pill and no swipe
        // (case handled by exhaustive switch). The provisional path is a
        // dedicated child view so it can own per-row `@State` drag offset for
        // a true 1:1 follow — a `@ViewBuilder` method can't hold state.
        if let entry, case let .provisional(deadline) = entry.state {
            ProvisionalCardRow(
                entryID: entry.id,
                deadline: deadline,
                onUndoCard: onUndoCard
            ) {
                content
            }
        } else {
            content
        }
    }

    /// Vertical stack of compact place rows — the design's `.ai-results` column.
    @ViewBuilder
    private func experienceResults(_ list: [Experience]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(list) { exp in
                ChatExperienceCard(experience: exp) { onSelectExperience(exp) }
            }
        }
    }

    /// City OS v2: vertical stack of 在地 event cards from `find_local_events`.
    @ViewBuilder
    private func eventResults(_ list: [CityEvent]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(list) { event in
                ChatEventCard(event: event) { tapped in
                    onShowEventOnMap?(tapped)
                }
            }
        }
    }
}

/// A provisional card row that follows the finger 1:1 on a left swipe as a
/// second undo affordance (the `UndoPill` is the primary one). Extracted into
/// its own view so it can own the per-row `@State` drag offset — a
/// `@ViewBuilder` method on `ChatCardStack` can't. The offset acts only on this
/// row; sibling rows in the `VStack` are unaffected.
@MainActor
private struct ProvisionalCardRow<Content: View>: View {
    let entryID: UUID
    let deadline: Date
    let onUndoCard: ((UUID) -> Void)?
    @ViewBuilder let content: Content

    /// Distance past which a release commits the undo. Also the point where the
    /// drag starts rubber-banding so overshoot feels resistant, not runaway.
    private static var undoThreshold: CGFloat { 80 }

    @State private var dragOffset: CGFloat = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        content
            .overlay(alignment: .topTrailing) {
                UndoPill(
                    deadline: deadline,
                    onUndo: { onUndoCard?(entryID) }
                )
                // Nudge into the card's top-right corner without clipping past
                // the padding on ChatCardStack itself.
                .padding(.trailing, 6)
                .padding(.top, 6)
            }
            .offset(x: dragOffset)
            .gesture(swipeGesture)
    }

    private var swipeGesture: some Gesture {
        DragGesture(minimumDistance: 12, coordinateSpace: .local)
            .onChanged { drag in
                // Left-only: ignore rightward pull entirely. Past the threshold,
                // the extra travel is dampened (0.3) so the card resists an
                // overshoot instead of flying off — classic rubber-band.
                let raw = min(0, drag.translation.width)
                if raw < -Self.undoThreshold {
                    let extra = raw + Self.undoThreshold
                    dragOffset = -Self.undoThreshold + extra * 0.3
                } else {
                    dragOffset = raw
                }
            }
            .onEnded { drag in
                // Commit on either enough travel or a fast predicted throw.
                let committed = drag.translation.width < -Self.undoThreshold
                    || drag.predictedEndTranslation.width < -Self.undoThreshold * 1.5
                let settle = Animation.spring(response: 0.3, dampingFraction: 0.8)
                if committed {
                    withAnimation(reduceMotion ? nil : settle) {
                        onUndoCard?(entryID)
                    }
                } else {
                    withAnimation(reduceMotion ? nil : settle) {
                        dragOffset = 0
                    }
                }
            }
    }
}

// Safe subscript so entries.count < cards.count degrades to nil instead of
// crashing — happens transiently when a new card lands between the
// snapshot the view rendered from and the updated entries projection.
private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
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
    /// Drives the one-shot "settle" on appear: the check ring sweeps closed and
    /// the badge pops in, so the chip reads as the live status line *finishing*
    /// rather than a new element hard-cutting in. reduceMotion lands it static.
    @State private var settled = false
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Button {
                guard summary.hasDetail else { return }
                Haptics.impact(.light)
                withAnimation(.easeInOut(duration: 0.22)) { expanded.toggle() }
            } label: {
                HStack(spacing: 7) {
                    ZStack {
                        // The ring that was spinning in AgentStatusLine sweeps
                        // shut here, handing off into the settled check badge.
                        Circle()
                            .trim(from: 0, to: settled ? 1 : 0.08)
                            .stroke(CT.verifiedGreen, style: StrokeStyle(lineWidth: 1.6, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                            .frame(width: 16, height: 16)
                            .opacity(settled ? 0 : 1)
                        Image(systemName: "checkmark")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(CT.verifiedGreen)
                            .frame(width: 16, height: 16)
                            .background(CT.verifiedGreen.opacity(settled ? 0.14 : 0), in: Circle())
                            .scaleEffect(settled ? 1 : 0.4)
                            .opacity(settled ? 1 : 0)
                    }
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
        .onAppear {
            if reduceMotion {
                settled = true
                return
            }
            // Throttle: stagger the settle spring by a deterministic per-chip
            // delay so a tool chain that unwinds several summaries in the same
            // frame doesn't fire N concurrent springs (read as visual noise).
            // Capped at ~240ms.
            let staggerDelay = Double(abs(summary.summary.hashValue) % 4) * 0.08
            DispatchQueue.main.asyncAfter(deadline: .now() + staggerDelay) {
                withAnimation(.spring(response: 0.5, dampingFraction: 0.75)) {
                    settled = true
                }
            }
        }
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
