import SwiftUI

/// Slice C endgame: the handoff card that appears when an Explore session
/// finishes with ≥1 result. Replaces the current 3-second toast with a
/// structured "here's your batch, what next?" surface.
///
/// Four CTAs, ranked by likely intent:
///   1. Ask Solo about these  — primary; the chat scoped to the added ids
///   2. Save as a walk        — freeze the batch into a route artifact
///   3. Expand radius         — the same-anchor next ring (disabled at max)
///   4. Clear these           — take it all back; useful if the batch was noisy
///
/// The card is dismissible: swipe down or tap outside minimizes it to a
/// pill anchored at the sheet top (see `pillSummary` at the bottom).
/// 10-second idle auto-minimize keeps the map surface uncluttered.
struct ExploreHandoffCard: View {
    let result: ExploreSession.HandoffResult
    let onAskSolo: () -> Void
    let onSaveWalk: () -> Void
    let onExpand: () -> Void
    let onClear: () -> Void
    let onDismiss: () -> Void

    /// Elapsed since presentation. Drives the 10-second auto-minimize.
    @State private var presentedAt: Date = Date()
    @State private var autoMinimizeTask: Task<Void, Never>?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 0) {
            Spacer()
            card
                .padding(.horizontal, 20)
                .padding(.bottom, 200)   // clear BottomInfoSheet peek
        }
        .transition(.move(edge: .bottom).combined(with: .opacity))
        .onAppear { scheduleAutoMinimize() }
        .onDisappear { autoMinimizeTask?.cancel() }
    }

    // MARK: - Card body

    private var card: some View {
        VStack(alignment: .leading, spacing: 14) {
            summary
            Divider()
                .background(CT.borderSubtle)
            ctaColumn
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(CT.surfaceWhite)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(CT.sunGold.opacity(0.35), lineWidth: 0.8)
        )
        .shadow(color: .black.opacity(0.18), radius: 18, y: 6)
        .accessibilityIdentifier("exploreHandoffCard")
    }

    private var summary: some View {
        let mainText: String = {
            if let city = result.cityName {
                return String(
                    format: NSLocalizedString(
                        "exploreMode.handoff.summary",
                        comment: "N places · N km · city"
                    ),
                    result.addedCount, result.finalRadiusKm, city
                )
            } else {
                return String(
                    format: NSLocalizedString(
                        "exploreMode.handoff.summaryNoCity",
                        comment: "N places · N km"
                    ),
                    result.addedCount, result.finalRadiusKm
                )
            }
        }()

        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: "sparkle.magnifyingglass")
                    .foregroundStyle(CT.sunGoldDeep)
                    .font(.system(size: 15, weight: .semibold))
                Text(mainText)
                    .ctDisplay(15, .semibold)
                    .foregroundStyle(CT.fgPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                Button(action: {
                    autoMinimizeTask?.cancel()
                    onDismiss()
                }) {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(CT.fgSubtle)
                        .frame(width: 26, height: 26)
                        .background(Circle().fill(CT.surfaceSunken))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text(NSLocalizedString("common.dismiss", comment: "Dismiss")))
            }
            if result.verifiedCount >= 2 {
                Text(String(
                    format: NSLocalizedString(
                        "exploreMode.handoff.verifiedSuffix",
                        comment: "N verified across sources"
                    ),
                    result.verifiedCount
                ))
                .ctMono(11, .medium)
                .foregroundStyle(CT.verifiedGreen)
            }
        }
    }

    private var ctaColumn: some View {
        VStack(spacing: 8) {
            // Primary CTA
            handoffButton(
                icon: "sparkles",
                title: NSLocalizedString("exploreMode.handoff.askSolo", comment: "Ask Solo about these"),
                isPrimary: true,
                enabled: true
            ) {
                autoMinimizeTask?.cancel()
                onAskSolo()
            }
            HStack(spacing: 8) {
                handoffButton(
                    icon: "figure.walk",
                    title: NSLocalizedString("exploreMode.handoff.saveWalk", comment: "Save as walk"),
                    isPrimary: false,
                    enabled: result.addedCount >= 2
                ) {
                    autoMinimizeTask?.cancel()
                    onSaveWalk()
                }
                handoffButton(
                    icon: "arrow.up.left.and.arrow.down.right",
                    title: NSLocalizedString("exploreMode.handoff.expand", comment: "Expand radius"),
                    isPrimary: false,
                    enabled: result.canExpand
                ) {
                    autoMinimizeTask?.cancel()
                    onExpand()
                }
            }
            Button(action: {
                autoMinimizeTask?.cancel()
                onClear()
            }) {
                Text(NSLocalizedString("exploreMode.handoff.clear", comment: "Clear these"))
                    .ctDisplay(12.5, .medium)
                    .foregroundStyle(CT.fgMuted)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("exploreHandoffClear")
        }
    }

    // MARK: - Button primitive

    @ViewBuilder
    private func handoffButton(
        icon: String,
        title: String,
        isPrimary: Bool,
        enabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .semibold))
                Text(title)
                    .ctDisplay(13, .semibold)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, isPrimary ? 12 : 10)
            .foregroundStyle(isPrimary ? Color.white : CT.accent)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(isPrimary ? CT.accent : CT.accentSoft)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(isPrimary ? Color.clear : CT.accentBorder, lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
        .opacity(enabled ? 1.0 : 0.4)
        .disabled(!enabled)
    }

    // MARK: - Auto-minimize

    /// How long the handoff card stays visible before self-dismissing.
    /// Rationale: an Explore session typically runs 25–30 s (China branch
    /// hits Amap synchronously then AI-synthesizes ~5–20 POIs). A 10 s
    /// timer was empirically dismissing the card BEFORE the first
    /// screenshot at t=35 s could catch it — the whole "result set as a
    /// first-class artifact" pattern paid no rent. 30 s buys the user
    /// enough time to read the summary, glance at the map cluster, and
    /// choose a CTA without feeling harassed by a lingering surface.
    static let autoMinimizeSeconds: TimeInterval = 30

    /// Auto-fires `onDismiss` after `autoMinimizeSeconds` so the user
    /// isn't held hostage by the card if they've already moved on. Any
    /// CTA cancels the task.
    private func scheduleAutoMinimize() {
        autoMinimizeTask?.cancel()
        autoMinimizeTask = Task {
            try? await Task.sleep(for: .seconds(Self.autoMinimizeSeconds))
            if Task.isCancelled { return }
            await MainActor.run { onDismiss() }
        }
    }
}

// MARK: - Preview

#Preview("Handoff · Futian · 7 places") {
    ZStack {
        Color(red: 0.20, green: 0.32, blue: 0.28).ignoresSafeArea()
        ExploreHandoffCard(
            result: .init(
                addedCount: 7,
                verifiedCount: 3,
                finalRadiusKm: 3,
                cityName: "Futian",
                addedIds: [],
                canExpand: true
            ),
            onAskSolo: {},
            onSaveWalk: {},
            onExpand: {},
            onClear: {},
            onDismiss: {}
        )
    }
}

#Preview("Handoff · nameless · 2 places · max radius") {
    ZStack {
        Color(red: 0.20, green: 0.32, blue: 0.28).ignoresSafeArea()
        ExploreHandoffCard(
            result: .init(
                addedCount: 2,
                verifiedCount: 0,
                finalRadiusKm: 100,
                cityName: nil,
                addedIds: [],
                canExpand: false
            ),
            onAskSolo: {},
            onSaveWalk: {},
            onExpand: {},
            onClear: {},
            onDismiss: {}
        )
    }
}
