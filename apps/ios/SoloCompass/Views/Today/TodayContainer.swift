import SwiftUI

/// Nomad OS B1 root container (design nomad-os-b1-today-home-20260719).
///
/// This is the app's new root when `FeatureFlags.todayHome` is on: a vertical
/// **Today** home flow with the map demoted to a full-screen layer that pulls
/// up from the bottom. When the flag is off, `body` falls straight through to
/// `CompassMapView()` — today's map-first form, byte-for-byte unchanged. That
/// pass-through is the rollback safety net for a form pivot that swaps the
/// app's loading point (`SoloCompassApp.body` renders `TodayContainer()` in
/// place of `CompassMapView()`, keeping every environment/cover modifier).
///
/// B1-a scope: container shell + pull-up map layer + rollback flag only. The
/// Today content here is a placeholder skeleton; StatusHeader / three-things /
/// nearby / seal-receipt接线 lands in B1-b..d. The map layer embeds the whole
/// existing `CompassMapView` (its BottomInfoSheet + 15 sheet slots ride along
/// untouched — we never reach into its `:182-209` refactor-forbidden zone).
///
/// The container reads no environment of its own: both branches resolve
/// `@Environment` from the injection chain that `SoloCompassApp` already
/// applies above this view, so `CompassMapView`'s nine `@Environment` reads
/// keep working whether it renders as the whole app or as the pulled-up layer.
public struct TodayContainer: View {
    public init() {}

    public var body: some View {
        if FeatureFlags.todayHome {
            TodayHomeScaffold()
                .debugRecordBranch(.todayHome)
        } else {
            // Rollback path: zero behavioural change from today's shipping form.
            CompassMapView()
                .debugRecordBranch(.mapFallback)
        }
    }

    /// Which branch `body` resolves to once installed in a graph. The type is
    /// available in every configuration so the `debugRecordBranch(_:)` call site
    /// type-checks in Release too; only the *recording* (the `@State`-like store
    /// below and the `.onAppear` write) is DEBUG-only.
    @MainActor enum RenderedBranch { case none, todayHome, mapFallback }

    #if DEBUG
    /// Test hook read by `TodayContainerTests` to assert the flag routes the
    /// root — including the flag-off rollback path (the shipping default).
    /// DEBUG-only and read-only; never affects production rendering.
    @MainActor static var debugRenderedBranch: RenderedBranch = .none
    #endif
}

private extension View {
    /// Records which `TodayContainer` branch rendered, for `TodayContainerTests`.
    /// In Release (`DEBUG` off) it compiles to a plain `self` — no reference to
    /// the DEBUG-only `debugRenderedBranch` store — so the release archive never
    /// touches it. An unconditional `.onAppear` reading that DEBUG-only member is
    /// exactly what failed the TestFlight archive; gating the write (while
    /// keeping the `RenderedBranch` argument type non-gated) makes the flag-off
    /// path Release-safe.
    @ViewBuilder
    func debugRecordBranch(_ branch: TodayContainer.RenderedBranch) -> some View {
        #if DEBUG
        onAppear { TodayContainer.debugRenderedBranch = branch }
        #else
        self
        #endif
    }
}

/// The Today-on, map-as-layer composition. Kept separate from `TodayContainer`
/// so the flag-off path never constructs any of this view's state.
private struct TodayHomeScaffold: View {
    @Environment(UserPreferences.self) private var preferences

    /// How far the map layer is pulled up, in points above its resting
    /// (fully-hidden-below) position. 0 = map parked off-screen, showing only
    /// its grab affordance; `fullTravel` = map covers the screen.
    @State private var mapReveal: CGFloat = 0
    /// Live drag delta, applied on top of `mapReveal` without committing it —
    /// mirrors BottomInfoSheet's offset-translation approach so the heavy map
    /// isn't re-laid-out every frame, only translated.
    @GestureState private var dragTranslation: CGFloat = 0

    /// Latches true the first time the map layer is pulled up. Until then the
    /// heavy `CompassMapView` is NOT instantiated — the parked layer is just a
    /// grab handle. This is what stops the map's cold-start `onAppear` from
    /// firing an Always-location prompt over the Today home on launch (B1-a
    /// finding): the map only requests location once the traveler actually
    /// reaches for it. Once mounted it stays mounted, so a rest back to parked
    /// never tears down and rebuilds the map (that would be expensive and
    /// re-trigger its bootstrap).
    @State private var mapEverRevealed = false

    /// Height of the peek handle that stays visible when the map is parked.
    private let handlePeek: CGFloat = 96

    public var body: some View {
        GeometryReader { proxy in
            let fullTravel = proxy.size.height
            // Committed reveal + live drag, clamped to [0, fullTravel].
            let reveal = min(max(mapReveal + dragTranslation, 0), fullTravel)
            let isMapOpen = reveal > fullTravel * 0.5
            // Mount the real map as soon as any pull begins; keep it mounted.
            let mapMounted = mapEverRevealed || reveal > 0

            ZStack(alignment: .bottom) {
                // ── Layer 1: Today home (placeholder skeleton for B1-a) ──
                todayHome
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(CT.pageAdaptive.ignoresSafeArea())
                    // Dim the home slightly as the map takes over, so the pull
                    // reads as "the map is coming forward", not a hard cut.
                    .overlay(
                        CT.scrimSoft
                            .opacity(Double(reveal / fullTravel))
                            .ignoresSafeArea()
                            .allowsHitTesting(false)
                    )

                // ── Layer 2: the existing map, as a pull-up full-screen layer ──
                mapLayer(
                    fullTravel: fullTravel,
                    reveal: reveal,
                    isOpen: isMapOpen,
                    mapMounted: mapMounted,
                    toggle: { mapReveal = isMapOpen ? 0 : fullTravel }
                )
                .offset(y: fullTravel - reveal)
            }
            .animation(.spring(response: 0.32, dampingFraction: 0.85), value: mapReveal)
            .onChange(of: reveal) { _, newValue in
                // Latch the mount the first time the layer is pulled at all.
                if newValue > 0 && !mapEverRevealed { mapEverRevealed = true }
            }
        }
        .ignoresSafeArea(.keyboard)
    }

    // MARK: Today home (real content lands slice by slice — three-things = B1-c)

    private var cityCode: String? { preferences.lastSelectedCity }

    private var todayHome: some View {
        VStack(spacing: 0) {
            // One-shot "your map has a new home" banner (B1-f) — shows once when
            // an existing user first lands on Today, then never again. Takes no
            // space after dismissal / for users who have already seen it.
            TodayNewHomeBanner()
                .padding(.top, Space.sm)

            // Sticky status header (B1-b) — stays out of the scroll region.
            TodayStatusHeader()

            // Scrolling body. NavigationStack so the nearby row can push the
            // full discovery list; its own bar is hidden to keep Today chrome
            // clean (the status header above is the app's real top).
            NavigationStack {
                ScrollView {
                    VStack(spacing: Space.lg) {
                        // Who's nearby (B1-d) — self-gates on FeatureFlags.companion.
                        TodayNearbyRow(cityCode: cityCode)

                        // Yesterday's seal receipt (B1-d) — renders only when a
                        // capsule was buried yesterday, else takes no space.
                        TodaySealReceipt()

                        // Today's three things (B1-c): work / now / tonight,
                        // picked from the current city's experiences.
                        TodayThreeThings()
                    }
                    .padding(.top, Space.lg)
                }
                .navigationDestination(for: NearbyDestination.self) { dest in
                    DiscoverListView(cityCode: dest.cityCode)
                }
                .toolbar(.hidden, for: .navigationBar)
                .background(CT.pageAdaptive)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: Map layer + grab handle

    private func mapLayer(
        fullTravel: CGFloat,
        reveal: CGFloat,
        isOpen: Bool,
        mapMounted: Bool,
        toggle: @escaping () -> Void
    ) -> some View {
        ZStack(alignment: .top) {
            if mapMounted {
                // The real map — only instantiated once the layer is reached
                // for, so its cold-start location request never fires under the
                // Today home (B1-a finding).
                CompassMapView()
            } else {
                // Parked, never-opened placeholder: a plain warm surface behind
                // the grab handle. No CompassMapView → no location prompt.
                CT.pageAdaptive
            }

            // Grab affordance / return-to-Today control, pinned to the layer's
            // top edge. When parked it's the "open map" handle; when open it's
            // the one-tap way back to Today (design §2 ⑤).
            mapHandle(isOpen: isOpen, toggle: toggle)
                .frame(maxWidth: .infinity)
                .padding(.top, Space.sm)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(CT.pageAdaptive)
        .clipShape(.rect(cornerRadius: isOpen ? 0 : Radius.xl, style: .continuous))
        .shadow(color: CT.scrimSoft, radius: isOpen ? 0 : 12, y: -4)
        .gesture(mapDragGesture(fullTravel: fullTravel))
    }

    private func mapHandle(isOpen: Bool, toggle: @escaping () -> Void) -> some View {
        Button {
            // Tap toggles between parked and open — a discoverable alternative
            // to the drag so the map is never trapped behind a gesture only.
            toggle()
        } label: {
            VStack(spacing: Space.xs) {
                Capsule()
                    .fill(CT.fgSubtle.opacity(0.6))
                    .frame(width: 40, height: 5)
                Text(NSLocalizedString(
                    isOpen ? "today.map.backToToday" : "today.map.open",
                    comment: "Map layer handle label: open the map / return to Today"
                ))
                .ctBody(13, .medium)
                .foregroundStyle(CT.textMutedAdaptive)
            }
            .padding(.vertical, Space.sm)
            .padding(.horizontal, Space.lg)
            .frame(height: handlePeek)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(NSLocalizedString(
            isOpen ? "today.map.backToToday" : "today.map.open",
            comment: "Map layer handle accessibility label"
        )))
    }

    private func mapDragGesture(fullTravel: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 8)
            .updating($dragTranslation) { value, state, _ in
                // Dragging up (negative translation.height) reveals more map;
                // invert so a positive `dragTranslation` means "more revealed".
                state = -value.translation.height
            }
            .onEnded { value in
                let projected = mapReveal - value.translation.height
                    - value.predictedEndTranslation.height * 0.25
                // Snap to whichever end of the travel the throw is closer to.
                mapReveal = projected > fullTravel * 0.5 ? fullTravel : 0
            }
    }
}
