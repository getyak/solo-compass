import SwiftUI

/// Slice C of the Explore-Mode redesign: the top-mounted status pill +
/// left-bottom Cancel FAB that make "we are in an Explore session"
/// legible as a mode, not just an in-flight network call.
///
/// Visible only while `session.state` is `.active`. The handoff card and
/// the cancelled banner render in their own overlays (see
/// `ExploreHandoffCard` + `ExploreCancelledBanner`) so this stays a
/// single-responsibility view.
///
/// Composition inside CompassMapView:
///
///   ZStack {
///     Map { ... exploreRadiusOverlay MapCircle stays there ... }
///     ExploreModeOverlay(session: viewModel.exploreSession,
///                        onCancel: { viewModel.exploreCancel() })
///     // handoff card + cancelled banner overlays follow
///   }
struct ExploreModeOverlay: View {
    let session: ExploreSession
    /// Optional city name pulled in from `viewModel.selectedCity` /
    /// resolved geocode. Keeps the ViewModel out of the overlay.
    let cityDisplayName: String?
    let onCancel: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        // .active-only. Other states clear the overlay so their cards
        // (handoff / cancelled) get a clean stage.
        guard case let .active(phase, radiusMeters, _, addedCount, verifiedCount) = session.state else {
            return AnyView(EmptyView())
        }
        return AnyView(
            VStack(alignment: .center, spacing: 0) {
                topPill(
                    phase: phase,
                    radiusMeters: radiusMeters,
                    addedCount: addedCount,
                    verifiedCount: verifiedCount
                )
                Spacer(minLength: 0)
                cancelBar
            }
            .allowsHitTesting(true)
            .accessibilityElement(children: .contain)
        )
    }

    // MARK: - Top pill

    /// Single-line status pill anchored near the top-safe area. Copy
    /// replaces the 5 legacy `explore.progress.*` variants with one
    /// template: "{verb} · {km} km · {addedCount} places".
    private func topPill(
        phase: ExploreSession.Phase,
        radiusMeters: Double,
        addedCount: Int,
        verifiedCount: Int
    ) -> some View {
        let km = Int((radiusMeters / 1000).rounded(.up))
        let verb = NSLocalizedString(phase.pillLocalizationKey, comment: "Explore Mode verb")
        let locale = cityDisplayName ?? NSLocalizedString(
            "exploreMode.pill.here", comment: "'here' fallback for the pill"
        )
        let countFragment: String = {
            // Rubric fix: before the first batch lands, show a "searching…"
            // fragment so the user isn't left staring at a static pill for
            // ~15 s wondering if the scan is stuck. Once addedCount > 0, the
            // fragment flips to the concrete "+N places" copy — same slot,
            // same font, so the transition reads as an update, not a jump.
            if addedCount == 0 {
                return NSLocalizedString(
                    "exploreMode.pill.searchingFragment",
                    comment: "'searching…' suffix while the scan has 0 places yet"
                )
            }
            let format = NSLocalizedString(
                "exploreMode.pill.countFragment",
                comment: "+N places (·  V verified) suffix on the top pill"
            )
            if verifiedCount >= 2 {
                return String(format: format, addedCount) + " · " + String(
                    format: NSLocalizedString(
                        "exploreMode.pill.verifiedFragment",
                        comment: "M verified fragment"
                    ),
                    verifiedCount
                )
            }
            return String(format: format, addedCount)
        }()

        return HStack(spacing: 10) {
            ScanningDots(reduceMotion: reduceMotion)
                .frame(width: 22, height: 12)
            VStack(alignment: .leading, spacing: 1) {
                Text("\(verb) · \(locale) · \(km) km")
                    .ctDisplay(13.5, .semibold)
                    .foregroundStyle(CT.fgPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                if !countFragment.isEmpty {
                    Text(countFragment)
                        .ctMono(10.5, .medium)
                        .foregroundStyle(CT.sunGoldDeep)
                        .lineLimit(1)
                        .transition(.opacity)
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(
            Capsule(style: .continuous)
                .fill(.regularMaterial)
        )
        .overlay(
            Capsule(style: .continuous)
                .strokeBorder(CT.sunGold.opacity(0.4), lineWidth: 0.8)
        )
        .shadow(color: .black.opacity(0.14), radius: 10, y: 4)
        // Rubric fix: 60 dropped the pill into the FilterBar chip row —
        // baseline evidence showed 'Now/...lo' peeking through either side.
        // 110 anchors the pill below both the status bar AND the FilterBar
        // so the two surfaces read as stacked, not overlapping.
        .padding(.top, 110)
        .padding(.horizontal, 20)
        .transition(.move(edge: .top).combined(with: .opacity))
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("exploreModePill")
        .accessibilityLabel(Text("\(verb) · \(locale) · \(km) km \(countFragment)"))
    }

    // MARK: - Cancel FAB row

    /// Bottom-left cancel affordance. Mirrors the Explore FAB placement
    /// so the two never coexist visually — during a session the Explore
    /// button is replaced by Cancel in the user's mental model.
    private var cancelBar: some View {
        HStack {
            Button(action: onCancel) {
                HStack(spacing: 6) {
                    Image(systemName: "xmark")
                        .font(.system(size: 13, weight: .semibold))
                    Text(NSLocalizedString("exploreMode.cancel", comment: "Cancel Explore"))
                        .ctDisplay(13, .semibold)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .foregroundStyle(CT.fgPrimary)
                .background(
                    Capsule(style: .continuous)
                        .fill(.regularMaterial)
                )
                .overlay(
                    Capsule(style: .continuous)
                        .strokeBorder(CT.borderDefault, lineWidth: 0.5)
                )
                .shadow(color: .black.opacity(0.14), radius: 8, y: 3)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("exploreModeCancel")
            Spacer()
        }
        .padding(.leading, 20)
        // The bottom padding is high enough that it clears the
        // BottomInfoSheet peek at any Dynamic-Type size. The caller
        // (CompassMapView) can override this with .safeAreaInset if it
        // wants tighter integration, but the overlay is self-contained
        // enough to not require it.
        .padding(.bottom, 200)
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }
}

// MARK: - Scanning dots animation

/// Three amber dots that fade in sequence. A lightweight substitute for a
/// ProgressView spinner that reads as "we're doing something" without
/// the medical UI of a system spinner. Falls back to a static row when
/// Reduce Motion is on.
private struct ScanningDots: View {
    let reduceMotion: Bool
    @State private var phase: Int = 0

    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<3, id: \.self) { i in
                Circle()
                    .fill(CT.sunGoldDeep)
                    .frame(width: 5, height: 5)
                    .opacity(reduceMotion ? 0.7 : opacityFor(i))
            }
        }
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: false)) {
                phase = 3
            }
        }
    }

    /// Rotating "1/3 lit" effect — dot `i` is bright when phase mod 3 == i.
    private func opacityFor(_ i: Int) -> Double {
        let cursor = (phase + i) % 3
        switch cursor {
        case 0: return 1.0
        case 1: return 0.55
        default: return 0.3
        }
    }
}

// MARK: - Previews

#Preview("Scanning · 3 km · +7") {
    ZStack {
        Color(red: 0.18, green: 0.32, blue: 0.28).ignoresSafeArea()
        ExploreModeOverlay(
            session: ExploreSession(state: .active(
                phase: .scanning,
                radiusMeters: 3000,
                anchor: .init(latitude: 22.5431, longitude: 114.0579),
                addedCount: 7,
                verifiedCount: 3
            )),
            cityDisplayName: "Futian",
            onCancel: {}
        )
    }
}

#Preview("Synthesizing · 6 km · +12") {
    ZStack {
        Color(red: 0.18, green: 0.32, blue: 0.28).ignoresSafeArea()
        ExploreModeOverlay(
            session: ExploreSession(state: .active(
                phase: .synthesizing,
                radiusMeters: 6000,
                anchor: .init(latitude: 22.5431, longitude: 114.0579),
                addedCount: 12,
                verifiedCount: 5
            )),
            cityDisplayName: "深圳",
            onCancel: {}
        )
    }
}

#Preview("Widening · 25 km") {
    ZStack {
        Color(red: 0.18, green: 0.32, blue: 0.28).ignoresSafeArea()
        ExploreModeOverlay(
            session: ExploreSession(state: .active(
                phase: .widening,
                radiusMeters: 25_000,
                anchor: .init(latitude: 22.5431, longitude: 114.0579),
                addedCount: 0,
                verifiedCount: 0
            )),
            cityDisplayName: nil,
            onCancel: {}
        )
    }
}
