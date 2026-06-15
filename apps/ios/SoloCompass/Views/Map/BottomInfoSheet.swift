import SwiftUI
import CoreLocation
#if canImport(UIKit)
import UIKit
#endif

// MARK: - SortMode

public enum SortMode: String, CaseIterable, Identifiable {
    case smart
    case distance
    case soloScore
    case now

    public var id: String { rawValue }

    var localizedTitle: String {
        switch self {
        case .smart:     return NSLocalizedString("sort.smart",     comment: "Sort: smart")
        case .distance:  return NSLocalizedString("sort.distance",  comment: "Sort: distance")
        case .soloScore: return NSLocalizedString("sort.soloScore", comment: "Sort: solo score")
        case .now:       return NSLocalizedString("sort.now",       comment: "Sort: now")
        }
    }

    /// US-030: VoiceOver accessibilityValue announcing the active sort mode
    /// (e.g. "Sorted by smart"). Keyed off the raw mode so each case maps to
    /// its own `sort.value.<mode>` localized string.
    var accessibilityValue: String {
        NSLocalizedString("sort.value.\(rawValue)", comment: "Sort accessibility value: current mode")
    }

    var symbol: String {
        switch self {
        case .smart:     return "sparkles"
        case .distance:  return "location.fill"
        case .soloScore: return "person.fill"
        case .now:       return "sunset.fill"
        }
    }

    var subtitleKey: String { "sort.subtitle.\(rawValue)" }
}

// MARK: - Constants

/// Unscaled (base, @ default Dynamic Type) detent heights. The effective
/// heights are derived from these via `BottomSheetDetent.scaledHeight` so that
/// at large Dynamic Type sizes (up to AX5) the sheet grows enough to show its
/// content without clipping.
private let basePeekHeight: CGFloat = 240
private let baseMidHeight: CGFloat = 500
private let baseFullHeight: CGFloat = 800
private let baseMinHeight: CGFloat = 120
/// Headroom above the largest detent so a drag can overshoot `full` slightly.
private let detentMaxHeadroom: CGFloat = 30
private let sheetCornerRadius: CGFloat = 20
private let scrimMaxOpacity: CGFloat = 0.18

/// Dynamic-Type scale factor applied to detent heights, derived from
/// `UIFontMetrics`. At the default content size this is 1.0; at AX5 it grows so
/// sheet content (rows, headers, toolbars) keeps pace with the enlarged text.
///
/// Exposed for tests so detent heights can be validated at extreme sizes.
enum BottomSheetDetentScale {
    /// Multiplier for the current (or supplied) trait collection's Dynamic Type
    /// size. Clamped to ≥1.0 so detents never shrink below their base height.
    static func factor(
        for traits: UITraitCollection? = nil
    ) -> CGFloat {
        #if canImport(UIKit)
        let metrics = UIFontMetrics.default
        let scaled: CGFloat
        if let traits {
            scaled = metrics.scaledValue(for: 1.0, compatibleWith: traits)
        } else {
            scaled = metrics.scaledValue(for: 1.0)
        }
        return max(1.0, scaled)
        #else
        return 1.0
        #endif
    }
}

#if canImport(UIKit)
extension DynamicTypeSize {
    /// Maps a SwiftUI `DynamicTypeSize` to the equivalent UIKit
    /// `UIContentSizeCategory`, so a trait collection can be built for
    /// `UIFontMetrics`-based scaling. SwiftUI does not expose this conversion.
    var uiContentSizeCategory: UIContentSizeCategory {
        switch self {
        case .xSmall:                       return .extraSmall
        case .small:                        return .small
        case .medium:                       return .medium
        case .large:                        return .large
        case .xLarge:                       return .extraLarge
        case .xxLarge:                      return .extraExtraLarge
        case .xxxLarge:                     return .extraExtraExtraLarge
        case .accessibility1:               return .accessibilityMedium
        case .accessibility2:               return .accessibilityLarge
        case .accessibility3:               return .accessibilityExtraLarge
        case .accessibility4:               return .accessibilityExtraExtraLarge
        case .accessibility5:               return .accessibilityExtraExtraExtraLarge
        @unknown default:                   return .large
        }
    }
}
#endif

// MARK: - Metrics

/// Hit-target sizing for the BottomInfoSheet, exposed for tests.
/// Apple HIG requires interactive controls to be at least 44×44 pt.
enum BottomSheetMetrics {
    /// Minimum width of the drag handle's tappable region.
    static let handleHitTargetWidth: CGFloat = 60
    /// Minimum height of the drag handle's tappable region (HIG minimum).
    static let handleHitTargetHeight: CGFloat = 44
}

// MARK: - Detent

public enum BottomSheetDetent: CaseIterable {
    case peek, mid, full

    /// Unscaled base height @ default Dynamic Type.
    var baseHeight: CGFloat {
        switch self {
        case .peek: return basePeekHeight
        case .mid: return baseMidHeight
        case .full: return baseFullHeight
        }
    }

    /// Detent height scaled for the given (or current) Dynamic Type size so
    /// content does not clip at large accessibility text sizes.
    func scaledHeight(for traits: UITraitCollection? = nil) -> CGFloat {
        baseHeight * BottomSheetDetentScale.factor(for: traits)
    }

    /// Effective `peek` detent height for the supplied Dynamic Type traits.
    /// Exposed so floating overlays (e.g. the selected-experience card) can sit
    /// clear of the sheet's resting height at any text size instead of relying
    /// on a hard-coded inset that clips at large Dynamic Type.
    static func peekHeight(for traits: UITraitCollection? = nil) -> CGFloat {
        BottomSheetDetent.peek.scaledHeight(for: traits)
    }

    static func nearest(
        to height: CGFloat,
        traits: UITraitCollection? = nil
    ) -> BottomSheetDetent {
        let all: [BottomSheetDetent] = [.peek, .mid, .full]
        return all.min(by: {
            abs($0.scaledHeight(for: traits) - height) < abs($1.scaledHeight(for: traits) - height)
        }) ?? .peek
    }

    /// Next detent in the peek → mid → full ladder, clamped at .full.
    var nextHigher: BottomSheetDetent {
        switch self {
        case .peek: return .mid
        case .mid: return .full
        case .full: return .full
        }
    }

    /// Previous detent in the full → mid → peek ladder, clamped at .peek.
    var nextLower: BottomSheetDetent {
        switch self {
        case .peek: return .peek
        case .mid: return .peek
        case .full: return .mid
        }
    }
}

// MARK: - BottomInfoSheet

public struct BottomInfoSheet<Content: View>: View {
    @State private var currentDetent: BottomSheetDetent = BottomInfoSheet.initialDetent

    /// Resting detent on appear. DEBUG-only `-expandSheet` launch argument forces
    /// the sheet to open at `.mid` on cold start so UI automation (idb/XCUITest)
    /// can reach the Routes/Nearby cards without synthesising an unreliable drag
    /// gesture to expand it (the custom drag-driven detent ignores idb swipes).
    /// Release builds always rest at `.peek`. Mirrors the `-startCity` debug hook.
    private static var initialDetent: BottomSheetDetent {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-expandSheet") { return .mid }
        #endif
        return .peek
    }
    @State private var dragOffset: CGFloat = 0
    @State private var isDragging: Bool = false
    @State var sortMode: SortMode = .smart
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private let aiHint: String
    private let count: Int
    private let isNowMode: Bool
    /// The experience featured in the peek summary card ("此刻最值得去"). When
    /// nil, the peek state shows `PeekEmptyCard` instead.
    private let peekExperience: Experience?
    /// Whether `peekExperience` is the AI smart pick (gold treatment + AI tag).
    private let isSmartPick: Bool
    /// Reference coordinate (user location or map center) for the peek card's
    /// distance + compass bearing.
    private let referenceCoordinate: CLLocationCoordinate2D?
    /// True while the floating preview card is up for a user-selected
    /// experience. The peek summary card ("此刻最值得去") fades out and yields
    /// to a lightweight hint so two competing "best pick" cards never stack —
    /// the user's active selection owns the focus.
    private let isPreviewActive: Bool
    private let content: (BottomSheetDetent, Binding<SortMode>) -> Content

    public init(
        aiHint: String,
        count: Int,
        isNowMode: Bool,
        peekExperience: Experience? = nil,
        isSmartPick: Bool = false,
        referenceCoordinate: CLLocationCoordinate2D? = nil,
        isPreviewActive: Bool = false,
        @ViewBuilder content: @escaping (BottomSheetDetent, Binding<SortMode>) -> Content
    ) {
        self.aiHint = aiHint
        self.count = count
        self.isNowMode = isNowMode
        self.peekExperience = peekExperience
        self.isSmartPick = isSmartPick
        self.referenceCoordinate = referenceCoordinate
        self.isPreviewActive = isPreviewActive
        self.content = content
    }

    /// Trait collection reflecting the current SwiftUI Dynamic Type size so
    /// detent heights scale via `UIFontMetrics` for accessibility text sizes.
    private var dynamicTypeTraits: UITraitCollection {
        UITraitCollection(preferredContentSizeCategory: dynamicTypeSize.uiContentSizeCategory)
    }

    private var detentBaseHeight: CGFloat {
        currentDetent.scaledHeight(for: dynamicTypeTraits)
    }

    private var scaledMinHeight: CGFloat {
        baseMinHeight * BottomSheetDetentScale.factor(for: dynamicTypeTraits)
    }

    private var scaledMaxHeight: CGFloat {
        BottomSheetDetent.full.scaledHeight(for: dynamicTypeTraits) + detentMaxHeadroom
    }

    private var scaledPeekHeight: CGFloat {
        BottomSheetDetent.peek.scaledHeight(for: dynamicTypeTraits)
    }

    private var scaledFullHeight: CGFloat {
        BottomSheetDetent.full.scaledHeight(for: dynamicTypeTraits)
    }

    private var displayHeight: CGFloat {
        let h = detentBaseHeight - dragOffset
        return max(scaledMinHeight, min(scaledMaxHeight, h))
    }

    private var scrimOpacity: CGFloat {
        let span = scaledFullHeight - scaledPeekHeight
        guard span > 0 else { return 0 }
        let fraction = (displayHeight - scaledPeekHeight) / span
        return max(0, min(1, fraction)) * scrimMaxOpacity
    }

    public var body: some View {
        ZStack(alignment: .bottom) {
            // Map scrim overlay
            Color.black
                .opacity(scrimOpacity)
                .ignoresSafeArea()
                .allowsHitTesting(false)

            // Sheet
            VStack(spacing: 0) {
                dragHandleArea
                peekContentArea
                    .padding(.horizontal, 16)
                    .padding(.top, 6)
                // The sort/count toolbar only belongs above the *list*; in the
                // peek state the summary card stands alone, so it is gated out.
                if currentDetent != .peek {
                    SortCountToolbar(count: count, isNowMode: isNowMode, sortMode: $sortMode)
                        .padding(.horizontal, 16)
                        .padding(.top, 8)
                }
                // Single unified scroll layer for every sheet section (Routes →
                // Create-route → Nearby). The sheet header rows above (handle,
                // peek/now-hint, toolbar) stay pinned; only the content closure
                // scrolls. Previously this was a bare `content + Spacer`, so the
                // Routes + Create-route rows were non-scrollable and only Nearby
                // carried its own inner ScrollView — a long Routes list pushed
                // Nearby off-screen with no way to scroll it back, and dragging up
                // to mid left the route cards stuck (the user's "滑不动"). Hosting
                // the whole closure in one ScrollView makes the sections a
                // continuous, naturally scrollable stream (like Apple Maps / Find
                // My) at *any* detent — mid scrolls the full list, no need to first
                // expand to full. At .peek the closure is empty, so this is a cheap
                // no-op.
                ScrollView {
                    content(currentDetent, $sortMode)
                        // Pin content to the top so a changing viewport height
                        // (mid→full during a drag) never re-centres the column —
                        // without this the rows visibly jump frame-to-frame as the
                        // sheet grows/shrinks, reading as a flicker.
                        .frame(maxWidth: .infinity, alignment: .top)
                        // Trailing breathing room so the last card never sits flush
                        // against the sheet's lower edge / home indicator.
                        .padding(.bottom, 28)
                }
                // Freeze the ScrollView while the handle is being dragged. The
                // sheet height animates every frame during a settle; an active
                // ScrollView would re-clamp its contentOffset against that moving
                // viewport and fight the drag, producing flicker. Re-enabled the
                // instant the drag ends.
                .scrollDisabled(isDragging)
                .scrollDismissesKeyboard(.interactively)
                // Show the indicator at mid/full as an affordance that more
                // content lies below; peek has no scroll content so it stays clean.
                .scrollIndicators(currentDetent == .peek ? .hidden : .automatic)
                // Suppress the empty bottom rubber-band when content is shorter
                // than the viewport, so a short list doesn't feel "loose".
                .scrollBounceBehavior(.basedOnSize)
            }
            .frame(maxWidth: .infinity)
            .frame(height: displayHeight)
            .background(
                UnevenRoundedRectangle(
                    topLeadingRadius: sheetCornerRadius,
                    bottomLeadingRadius: 0,
                    bottomTrailingRadius: 0,
                    topTrailingRadius: sheetCornerRadius
                )
                .fill(.ultraThinMaterial)
            )
        }
        // Animate ONLY the discrete detent settle (which changes once, on
        // release), never the continuously finger-driven `displayHeight`.
        // Watching `displayHeight` meant every drag frame nudged a value an
        // active spring was tracking, so the spring kept restarting-then-being-
        // interrupted frame to frame — the sheet edge jittered larger/smaller
        // (the "flicker"). Pinned to `currentDetent`, the drag is pure immediate
        // finger-tracking (no animation) and only the release-to-nearest-detent
        // gets the spring.
        .animation(.spring(response: 0.3, dampingFraction: 0.85), value: currentDetent)
    }

    // MARK: - Peek content

    /// Peek state shows the "此刻最值得去" summary card (or the empty card);
    /// every other detent reverts to the compact now-hint row above the list.
    @ViewBuilder
    private var peekContentArea: some View {
        if currentDetent == .peek {
            peekSummaryArea
        } else {
            NowHintRow(hint: aiHint)
        }
    }

    /// Golden section label + the summary card. Tapping anywhere in this area —
    /// the label, the card, or the surrounding whitespace — expands the sheet to
    /// `.mid`. `currentDetent` is assigned directly; the outer ZStack's
    /// `.animation(value:)` provides the spring, so no `withAnimation` wrapper is
    /// used here (that would fight the implicit animation).
    @ViewBuilder
    private var peekSummaryArea: some View {
        VStack(alignment: .leading, spacing: 8) {
            peekHeaderLabel
            if isPreviewActive {
                // A floating preview card already owns the "best pick" focus —
                // collapse this card to a one-line hint so the two never
                // compete on screen. The sheet stays pull-up-able.
                previewActiveHint
            } else if let experience = peekExperience {
                PeekSummaryCard(
                    experience: experience,
                    isSmartPick: isSmartPick,
                    referenceCoordinate: referenceCoordinate,
                    onTap: {
                        currentDetent = .mid
                        #if canImport(UIKit)
                        Haptics.selection()
                        #endif
                    }
                )
            } else {
                PeekEmptyCard()
            }
        }
        .animation(.easeInOut(duration: 0.25), value: isPreviewActive)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .onTapGesture {
            currentDetent = .mid
            #if canImport(UIKit)
            Haptics.selection()
            #endif
        }
    }

    /// Golden "此刻最值得去" header, mirroring `RouteNowSectionHeader`'s left side
    /// (sparkles + uppercase sun-gold-deep display text).
    private var peekHeaderLabel: some View {
        HStack(spacing: 7) {
            Image(systemName: "sparkles")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(CT.sunGoldDeep)
            Text(NSLocalizedString("peek.pick.header", comment: "此刻最值得去 peek section header"))
                .font(CT.display(11, .bold))
                .tracking(1.3)
                .textCase(.uppercase)
                .foregroundStyle(CT.sunGoldDeep)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 4)
        .accessibilityAddTraits(.isHeader)
    }

    /// One-line stand-in shown in place of the peek summary card while a
    /// floating preview card is active, so the sheet's peek region keeps a
    /// stable height and remains tappable to pull up the full list.
    private var previewActiveHint: some View {
        HStack(spacing: 6) {
            Image(systemName: "hand.tap")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
            Text(NSLocalizedString(
                "peek.preview.active.hint",
                comment: "Shown in the peek area while a preview card is up"
            ))
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .lineLimit(1)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .transition(.opacity)
    }

    // MARK: - Drag Handle

    private var dragHandleArea: some View {
        // ≥44pt hit area (60×44) containing a 36×4 visible pill so VoiceOver /
        // Switch Control users can reliably grab the handle (Apple HIG).
        ZStack {
            Capsule()
                .fill(Color.secondary.opacity(0.5))
                .frame(width: 36, height: 4)
        }
        .frame(
            minWidth: BottomSheetMetrics.handleHitTargetWidth,
            minHeight: BottomSheetMetrics.handleHitTargetHeight
        )
        .contentShape(Rectangle())
        .frame(maxWidth: .infinity)
        .gesture(
            DragGesture(minimumDistance: 4)
                .onChanged { value in
                    isDragging = true
                    dragOffset = value.translation.height
                }
                .onEnded { value in
                    let projectedHeight = detentBaseHeight - value.predictedEndTranslation.height
                    let clampedHeight = max(scaledMinHeight, min(scaledMaxHeight, projectedHeight))
                    // Settle to the nearest detent with an EXPLICIT spring. Both
                    // `currentDetent` and `dragOffset` feed `displayHeight`, but the
                    // implicit `.animation(value: currentDetent)` only fires when the
                    // detent actually changes. On a small drag that lands back on the
                    // same detent, `currentDetent` is unchanged, so zeroing
                    // `dragOffset` outside an animation would snap the sheet back with
                    // no spring (the "生硬" settle). Wrapping the state collapse in
                    // `withAnimation` guarantees the release always springs home —
                    // whether or not the detent changed.
                    // Keep `isDragging` true until the settle animation starts so
                    // `.scrollDisabled(isDragging)` doesn't release mid-spring and
                    // let the ScrollView swallow the remaining bounce.
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                        isDragging = false
                        currentDetent = BottomSheetDetent.nearest(to: clampedHeight, traits: dynamicTypeTraits)
                        dragOffset = 0
                    }
                }
        )
        // A discrete tap on the handle steps up one detent. `DragGesture`'s
        // `minimumDistance: 4` means a tap never registers as a drag, so the two
        // gestures coexist without conflict.
        .simultaneousGesture(
            TapGesture().onEnded {
                currentDetent = currentDetent.nextHigher
                #if canImport(UIKit)
                Haptics.selection()
                #endif
            }
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(NSLocalizedString("sheet.handle", comment: "Bottom sheet drag handle")))
        .accessibilityHint(Text(NSLocalizedString("sheet.handle.hint", comment: "Tap to expand, drag to resize")))
        .accessibilityAddTraits(.allowsDirectInteraction)
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment:
                currentDetent = currentDetent.nextHigher
            case .decrement:
                currentDetent = currentDetent.nextLower
            @unknown default:
                break
            }
        }
    }
}

// MARK: - NowHintRow

struct NowHintRow: View {
    let hint: String

    @Environment(BestNowClock.self) private var clock

    /// Locale-aware short time string (respects the device's 12/24h preference).
    /// Cached as a static so a single formatter is reused across re-evaluations.
    private static let formatter: DateFormatter = {
        let f = DateFormatter()
        f.timeStyle = .short
        f.dateStyle = .none
        return f
    }()

    /// Testable helper — formats `date` using the given locale.
    static func timeString(for date: Date, locale: Locale = .current) -> String {
        let f = DateFormatter()
        f.timeStyle = .short
        f.dateStyle = .none
        f.locale = locale
        return f.string(from: date)
    }

    private var formattedTime: String {
        Self.timeString(for: clock.tick)
    }

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "sunset.fill")
                .font(.caption)
                .foregroundStyle(.orange)
            Text(hint)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Spacer(minLength: 4)
            Text(formattedTime)
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text("\(hint) \(formattedTime)"))
    }
}

// MARK: - SortCountToolbar

struct SortCountToolbar: View {
    let count: Int
    let isNowMode: Bool
    @Binding var sortMode: SortMode
    @State private var showSortSheet = false
    @State private var pulse = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack {
            sortButton
            Spacer()
            countBadge
                .scaleEffect(pulse ? 1.12 : 1.0)
                .animation(.spring(response: 0.3, dampingFraction: 0.6), value: pulse)
        }
        .sheet(isPresented: $showSortSheet) {
            SortModeSheet(sortMode: $sortMode)
                .presentationDetents([.height(300)])
                .presentationDragIndicator(.visible)
        }
        .onChange(of: sortMode) { _, _ in
            #if canImport(UIKit)
            Haptics.selection()
            #endif
            guard !reduceMotion else { return }
            pulse = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                pulse = false
            }
        }
    }

    private var sortButton: some View {
        Button {
            #if canImport(UIKit)
            Haptics.selection()
            #endif
            showSortSheet = true
        } label: {
            HStack(spacing: 4) {
                Text(sortMode.localizedTitle)
                    .font(.caption.weight(.medium))
                Image(systemName: "chevron.down")
                    .font(.caption2.weight(.semibold))
            }
            .foregroundStyle(.primary)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Capsule().fill(.regularMaterial))
        }
        .buttonStyle(SortRowButtonStyle())
        .accessibilityLabel(Text(NSLocalizedString("sheet.sort.button", comment: "Sort")))
        .accessibilityValue(Text(sortMode.accessibilityValue))
    }

    private var countBadge: some View {
        let key = isNowMode ? "sheet.count.now" : "sheet.count.nearby"
        let label = String(
            format: NSLocalizedString(key, comment: "Count badge"),
            count
        )
        return Text(label)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Capsule().fill(Color.secondary.opacity(0.12)))
            .accessibilityLabel(Text(label))
    }
}

// MARK: - SortRowButtonStyle

/// Scales down ~4% on press for tactile feedback matching FilterBarView's PressableButtonStyle.
private struct SortRowButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1.0)
            .animation(.spring(response: 0.25, dampingFraction: 0.6), value: configuration.isPressed)
    }
}

// MARK: - SortModeSheet

struct SortModeSheet: View {
    @Binding var sortMode: SortMode
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(NSLocalizedString("sheet.sort.button", comment: "Sort sheet title"))
                .font(.headline)
                .padding(.horizontal, 20)
                .padding(.top, 20)
                .padding(.bottom, 12)

            ForEach(SortMode.allCases) { mode in
                Button {
                    #if canImport(UIKit)
                    Haptics.selection()
                    #endif
                    withAnimation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.7)) {
                        sortMode = mode
                    }
                    dismiss()
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: mode.symbol)
                            .foregroundStyle(.secondary)
                            .frame(width: 28)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(mode.localizedTitle)
                                .font(.body)
                                .foregroundStyle(.primary)
                            Text(NSLocalizedString(mode.subtitleKey, comment: "Sort mode subtitle"))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        if sortMode == mode {
                            Image(systemName: "checkmark")
                                .font(.body.weight(.semibold))
                                .foregroundStyle(Color.accentColor)
                                .transition(.scale.combined(with: .opacity))
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 14)
                    .background(
                        Group {
                            if sortMode == mode {
                                RoundedRectangle(cornerRadius: 10)
                                    .fill(Color.accentColor.opacity(0.10))
                                    .padding(.horizontal, 8)
                            }
                        }
                    )
                    .contentShape(Rectangle())
                }
                .buttonStyle(SortRowButtonStyle())
                .accessibilityElement(children: .combine)

                if mode.id != SortMode.allCases.last?.id {
                    Divider()
                        .padding(.leading, 20)
                }
            }
            Spacer()
        }
        .accessibilityElement(children: .contain)
    }
}

// MARK: - NearbyExperienceRow

/// Single card in the '附近' section of the BottomInfoSheet.
///
/// Card layout (mirrors the route-card chrome so the list reads as a stack of
/// discrete cards rather than ruled rows): a left category color-bar, a filled
/// category disc, the title + romanized·local subtitle, a chip row
/// (walk-time · Solo score · 此刻最佳), and a trailing distance + compass arrow.
struct NearbyExperienceRow: View {
    let experience: Experience
    let isSmartPick: Bool
    /// Distance in meters from the user's current location (or map center).
    let distanceMeters: Double?
    /// True when the experience's bestTimes include the current clock hour (Now sort mode only).
    let isOpenNow: Bool
    /// Live "best now / closing soon" chip state, resolved by the parent section
    /// from the shared `BestNowClock` so the countdown stays current. Only read
    /// when `isOpenNow` is true; nil leaves the chip in its plain form.
    var bestNowChipState: BestNowChipState? = nil
    /// Tapping the card jumps straight to the detail sheet.
    let onTap: () -> Void
    /// Long-pressing the card floats the quick preview card instead. Optional so
    /// existing callers that only want a tap action keep compiling.
    var onLongPress: (() -> Void)? = nil
    /// "问 Solo" context-menu action — opens a chat scoped to this experience.
    /// Optional so callers that don't wire chat keep compiling.
    var onAskSolo: (() -> Void)? = nil

    @State private var pressed = false
    @State private var pulsing = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(LocationService.self) private var locationService
    @Environment(UserPreferences.self) private var preferences

    private var isNearby: Bool {
        guard let m = distanceMeters else { return false }
        return m < 150
    }

    private static let distanceFormatter: MeasurementFormatter = {
        let f = MeasurementFormatter()
        f.unitOptions = .naturalScale
        f.unitStyle = .short
        f.numberFormatter.maximumFractionDigits = 1
        return f
    }()

    // MARK: Proximity helpers (mirrors FavoritesListView.Proximity)

    private enum Proximity {
        case near, mid, far

        static func from(meters: Double) -> Proximity {
            if meters <= 1000 { return .near }
            if meters <= 5000 { return .mid }
            return .far
        }

        var dotColor: Color {
            switch self {
            case .near: return CT.verifiedGreenDot
            case .mid: return CT.toneForming
            case .far: return CT.fgSubtle
            }
        }

        /// Localized density word shown next to the chip row (稀疏 / 中等 / 较远),
        /// mirroring the screenshot's proximity caption.
        var labelKey: String {
            switch self {
            case .near: return "nearby.proximity.sparse"
            case .mid:  return "nearby.proximity.moderate"
            case .far:  return "nearby.proximity.far"
            }
        }
    }

    private var proximity: Proximity? {
        guard let m = distanceMeters else { return nil }
        return Proximity.from(meters: m)
    }

    // MARK: Bearing helpers

    private var relativeBearing: Double? {
        guard let coord = experience.coordinate else { return nil }
        return locationService.relativeBearing(to: coord)
    }

    /// 8-point compass label derived from an absolute bearing (0 = N, clockwise).
    private func compassPoint(for absoluteBearing: Double) -> String {
        let points = [
            NSLocalizedString("compass.N",  comment: "Compass point: North"),
            NSLocalizedString("compass.NE", comment: "Compass point: North-East"),
            NSLocalizedString("compass.E",  comment: "Compass point: East"),
            NSLocalizedString("compass.SE", comment: "Compass point: South-East"),
            NSLocalizedString("compass.S",  comment: "Compass point: South"),
            NSLocalizedString("compass.SW", comment: "Compass point: South-West"),
            NSLocalizedString("compass.W",  comment: "Compass point: West"),
            NSLocalizedString("compass.NW", comment: "Compass point: North-West"),
        ]
        let index = Int((absoluteBearing + 22.5) / 45) % 8
        return points[index]
    }

    private var compassDirectionSuffix: String? {
        guard let coord = experience.coordinate,
              let absolute = locationService.bearing(to: coord) else { return nil }
        let point = compassPoint(for: absolute)
        let fmt = NSLocalizedString("nearby.direction.suffix",
                                    comment: "Compass direction suffix, e.g. 'to the North'")
        return String(format: fmt, point)
    }

    var body: some View {
        Button {
            #if canImport(UIKit)
            Haptics.selection()
            if !reduceMotion {
                withAnimation(.spring(response: 0.18, dampingFraction: 0.5)) { pressed = true }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
                    withAnimation(.spring(response: 0.18, dampingFraction: 0.5)) { pressed = false }
                }
            }
            #endif
            onTap()
        } label: {
            HStack(alignment: .top, spacing: 12) {
                categoryDisc
                VStack(alignment: .leading, spacing: 7) {
                    titleStack
                    chipRow
                }
                Spacer(minLength: 4)
                distanceColumn
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(cardBackground)
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(isSmartPick ? CT.accentBorder : CT.borderSubtle, lineWidth: 0.5)
            )
            .overlay(alignment: .leading) {
                // Left color-bar: golden for smart picks, else the category tint.
                UnevenRoundedRectangle(
                    topLeadingRadius: 14, bottomLeadingRadius: 14,
                    bottomTrailingRadius: 0, topTrailingRadius: 0,
                    style: .continuous
                )
                .fill(isSmartPick ? CT.sunGold : experience.category.color)
                .frame(width: 3)
            }
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .shadow(color: .black.opacity(0.04), radius: 1, x: 0, y: 1)
        }
        .buttonStyle(.plain)
        .scaleEffect(pressed ? 0.97 : 1.0)
        // Long-press now raises the native context menu: a warm-amber preview
        // card (key info + hero image) floating over a blurred backdrop, plus a
        // quick-action menu (details · show on map · favorite · navigate · 问
        // Solo). This replaces the former custom floating-card long-press —
        // `onLongPress` is still wired as the "show on map" action so that
        // behavior is preserved, just relocated into the menu.
        .contextMenu {
            cardContextMenu
        } preview: {
            ExperiencePreviewCard(
                experience: experience,
                distanceMeters: distanceMeters,
                bestNowChipState: bestNowChipState
            )
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityHint(Text(NSLocalizedString("experience.card.hint", comment: "Double tap to view details")))
        .accessibilityAction(named: Text(NSLocalizedString("experience.card.preview.a11y", comment: "Preview action: float the quick preview card"))) {
            onLongPress?()
        }
    }

    /// Quick actions for the long-press context menu. Favorite + navigate act
    /// inline (preferences / NavigationLauncher); details, show-on-map, and 问
    /// Solo route through the caller's handlers.
    @ViewBuilder
    private var cardContextMenu: some View {
        Button {
            onTap()
        } label: {
            Label(NSLocalizedString("menu.viewDetails", comment: "View details"), systemImage: "doc.text.magnifyingglass")
        }

        if let onLongPress {
            Button {
                onLongPress()
            } label: {
                Label(NSLocalizedString("menu.showOnMap", comment: "Show on map"), systemImage: "mappin.and.ellipse")
            }
        }

        if let onAskSolo {
            Button {
                onAskSolo()
            } label: {
                Label(NSLocalizedString("menu.askSolo", comment: "Ask Solo about this place"), systemImage: "sparkles")
            }
        }

        Divider()

        let favorited = preferences.isFavorited(experience.id)
        Button {
            Haptics.impact(.light)
            preferences.toggleFavorite(experience.id)
        } label: {
            Label(
                favorited
                    ? NSLocalizedString("menu.unfavorite", comment: "Remove from saved")
                    : NSLocalizedString("menu.favorite", comment: "Save place"),
                systemImage: favorited ? "heart.slash" : "heart"
            )
        }

        if let coord = experience.coordinate {
            Button {
                NavigationLauncher.open(app: .appleMaps, coordinate: coord, name: experience.title)
            } label: {
                Label(NSLocalizedString("menu.navigate", comment: "Navigate there"), systemImage: "arrow.triangle.turn.up.right.diamond")
            }
        }
    }

    // MARK: - Sub-views

    private var categoryDisc: some View {
        ZStack {
            Circle()
                .fill(experience.category.color)
                .frame(width: 40, height: 40)
            Image(systemName: experience.category.symbol)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(.white)
        }
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private var titleStack: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(experience.title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(CT.fgPrimary)
                // Long names like "Savor Japanese small plates al…" were cut to
                // one line; allow two and shrink slightly before truncating.
                .lineLimit(2)
                .minimumScaleFactor(0.85)

            let sub = subtitleText
            if !sub.isEmpty {
                Text(sub)
                    .font(.caption)
                    .foregroundStyle(CT.fgMuted)
                    .lineLimit(1)
            }
        }
    }

    /// Horizontal chip row: walk-time · Solo score · (此刻最佳) · proximity word.
    private var chipRow: some View {
        HStack(spacing: 6) {
            if let meters = distanceMeters, meters < 1500 {
                walkTimeChip(meters: meters)
            }
            soloScoreChip
            if isOpenNow {
                bestNowChip
                    .transition(
                        reduceMotion ? .identity :
                            .scale(scale: 0.8).combined(with: .opacity)
                    )
            }
            // The proximity word ("Far"/"Quiet") duplicated the precise distance
            // already shown in `distanceColumn` and read as a negative signal for
            // a solo traveler. The km figure on the right is clearer; drop the word.
        }
        .animation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.7), value: isOpenNow)
    }

    /// Neutral chip: estimated walk minutes (≈ 80 m/min) for nearby experiences.
    private func walkTimeChip(meters: Double) -> some View {
        let minutes = max(1, Int((meters / 80).rounded()))
        let label = String(
            format: NSLocalizedString("nearby.chip.walkMin", comment: "Walk minutes chip, e.g. '4 分钟'"),
            minutes
        )
        return HStack(spacing: 3) {
            Image(systemName: "figure.walk")
                .font(.system(size: 9.5, weight: .semibold))
            Text(label)
                .font(.caption2.weight(.medium))
        }
        .foregroundStyle(CT.fgMuted)
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(Capsule().fill(CT.surfaceSunken))
    }

    /// Green chip: Solo score (e.g. "Solo 7.5").
    private var soloScoreChip: some View {
        Text(
            String(
                format: NSLocalizedString("nearby.chip.solo", comment: "Solo score chip, e.g. 'Solo 7.5'"),
                experience.soloScore.overall
            )
        )
        .font(.caption2.weight(.bold))
        .foregroundStyle(CT.verifiedGreen)
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(Capsule().fill(CT.verifiedGreen.opacity(0.12)))
    }

    /// Golden chip: 此刻最佳 — shown when the experience is open in the current
    /// hour. Flips to an amber "Closing · Nm" countdown when the active window
    /// has ≤ 45 minutes left, matching the detail card and Saved list.
    private var bestNowChip: some View {
        let state = bestNowChipState ?? BestNowChipState(isClosingSoon: false, minutesLeft: nil)
        return HStack(spacing: 3) {
            Image(systemName: state.symbol)
                .font(.system(size: 9, weight: .semibold))
            Text(state.label)
                .font(.caption2.weight(.semibold))
                .monospacedDigit()
                .contentTransition(reduceMotion ? .identity : .numericText())
        }
        .foregroundStyle(state.foreground)
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(Capsule().fill(state.background))
    }

    private var subtitleText: String {
        let parts = [
            experience.location.placeNameRomanized,
            experience.location.placeNameLocal
        ].compactMap { $0?.isEmpty == false ? $0 : nil }
        if parts.isEmpty {
            return experience.location.addressHint ?? ""
        }
        return parts.joined(separator: " · ")
    }

    /// Trailing column: compass arrow over the formatted distance, right-aligned.
    private var distanceColumn: some View {
        let bearing = relativeBearing
        let hasLiveBearing = bearing != nil
        let arrowColor: AnyShapeStyle = isNearby
            ? AnyShapeStyle(CT.sunGoldDeep)
            : (hasLiveBearing ? AnyShapeStyle(CT.fgMuted) : AnyShapeStyle(CT.fgSubtle))
        return VStack(alignment: .trailing, spacing: 4) {
            Image(systemName: "location.north.line.fill")
                .font(.caption2)
                .foregroundStyle(arrowColor)
                .rotationEffect(.degrees(bearing ?? 0))
                .animation(reduceMotion ? nil : .easeInOut(duration: 0.3), value: bearing)
                .scaleEffect(pulsing ? 1.18 : 1.0)
            if let meters = distanceMeters {
                Text(formattedDistance(meters))
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(isNearby ? AnyShapeStyle(CT.sunGoldDeep) : AnyShapeStyle(CT.fgSubtle))
                if isNearby {
                    Text(NSLocalizedString("peek.card.almostThere", comment: "Almost there micro-label shown when < 150m"))
                        .font(.caption2)
                        .foregroundStyle(CT.sunGoldDeep)
                }
            }
        }
        .accessibilityHidden(true)
        .onAppear { startNearbyPulseIfNeeded() }
        .onChange(of: isNearby) { _, nearby in
            if nearby {
                startNearbyPulseIfNeeded()
            } else {
                withAnimation(.default) { pulsing = false }
            }
        }
    }

    private func startNearbyPulseIfNeeded() {
        guard isNearby, !reduceMotion else {
            pulsing = false
            return
        }
        withAnimation(.easeInOut(duration: 0.85).repeatForever(autoreverses: true)) {
            pulsing = true
        }
    }

    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: 14, style: .continuous)
            .fill(isSmartPick ? AnyShapeStyle(smartPickGradient) : AnyShapeStyle(CT.surfaceWhite))
    }

    private var smartPickGradient: LinearGradient {
        LinearGradient(
            colors: [CT.sunGoldSoft.opacity(0.55), CT.surfaceWhite],
            startPoint: .leading,
            endPoint: .trailing
        )
    }

    private var accessibilityLabel: Text {
        var label = experience.title
        label += ", Solo \(String(format: "%.1f", experience.soloScore.overall))"
        if let meters = distanceMeters {
            label += ", \(formattedDistance(meters))"
        }
        if let dirSuffix = compassDirectionSuffix {
            label += ", \(dirSuffix)"
        }
        if isSmartPick {
            label += ", " + NSLocalizedString("sheet.nearby.smartPick.a11y", comment: "AI pick")
        }
        if isOpenNow {
            // Prefer the live closing-soon phrasing when the window is winding
            // down; otherwise the plain open-now cue.
            if let state = bestNowChipState, state.isClosingSoon {
                label += ", " + state.accessibilityLabel
            } else {
                label += ", " + NSLocalizedString("sheet.nearby.openNow.a11y", comment: "Open now accessibility")
            }
        }
        if isNearby {
            label += ", " + NSLocalizedString("peek.card.almostThere.a11y", comment: "VoiceOver: almost there proximity cue")
        }
        return Text(label)
    }

    private func formattedDistance(_ meters: Double) -> String {
        Self.distanceFormatter.string(from: Measurement(value: meters, unit: UnitLength.meters))
    }
}

// MARK: - SheetSectionSeparator

/// US-036: Visual divider between the Routes and Nearby sections in the
/// BottomInfoSheet. Renders an inset (leading-padded) divider followed by a
/// localized section title, so the information hierarchy between routes and
/// nearby experiences is explicit. The two titles live behind the
/// `sheet.section.routes` / `sheet.section.nearby` localized keys.
struct SheetSectionSeparator: View {
    /// Localization key for the section title (e.g. `sheet.section.nearby`).
    let titleKey: String
    /// When true, the leading inset divider is drawn above the title. The very
    /// first section (Routes) omits it so the sheet doesn't open with a divider.
    let showsDivider: Bool

    /// Leading inset (pt) applied to the divider so it reads as a section break
    /// rather than a full-bleed rule, matching the row dividers below it.
    static let dividerInset: CGFloat = 16

    init(titleKey: String, showsDivider: Bool = true) {
        self.titleKey = titleKey
        self.showsDivider = showsDivider
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if showsDivider {
                Divider()
                    .padding(.leading, Self.dividerInset)
                    .padding(.vertical, 8)
            }
            Text(NSLocalizedString(titleKey, comment: "Bottom sheet section title"))
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .tracking(0.5)
                .padding(.horizontal, 16)
                .padding(.bottom, 6)
                .accessibilityAddTraits(.isHeader)
        }
    }
}

// MARK: - RoutesSection

/// '路线' section rendered inside BottomInfoSheet above 附近.
/// Shows RouteStore.nearby routes. When isNowFilter is true only bestNow routes appear.
struct RoutesSection: View {
    let routes: [Route]
    let isNowFilter: Bool
    let onSelectRoute: (Route) -> Void

    private var displayed: [Route] {
        // Now-context uses the runtime check (derived from bestStartHour) so the
        // 此刻適合 section surfaces routes inside their window — the static
        // `bestNow` seed flag is all-false today, which would empty the section.
        isNowFilter ? routes.filter { $0.isBestNow() } : routes
    }

    var body: some View {
        let items = displayed
        Group {
            if !items.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    // US-036: Routes is the first section, so its header omits the
                    // leading inset divider (the sheet must not open with a rule).
                    // RouteCard now carries its own card chrome (.sc-route-card:
                    // white fill, border, shadow), so rows are separated by 10pt
                    // spacing rather than full-bleed dividers.
                    //
                    // In now-context the section gets a dedicated golden header
                    // (sparkles + 「路線 · 此刻適合」+ AI · NOW), mirroring the
                    // 此刻精選 AI region — see styles.css `.sc-section-label .lhs.now`.
                    if isNowFilter {
                        RouteNowSectionHeader()
                    } else {
                        SheetSectionSeparator(titleKey: "sheet.section.routes", showsDivider: false)
                    }
                    ForEach(items) { route in
                        Button { onSelectRoute(route) } label: {
                            RouteCard(route: route, nowContext: isNowFilter)
                        }
                        // PressableButtonStyle drives the press-scale via the
                        // system tap recognizer. RouteCard no longer owns a local
                        // zero-distance DragGesture (which swallowed the tap inside
                        // this ScrollView — see RouteCard), so the tap now reaches
                        // this Button's action and opens the route detail.
                        .buttonStyle(PressableButtonStyle(pressedScale: 0.985))
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
            }
        }
    }
}

// MARK: - RouteNowSectionHeader

/// Dedicated golden header for the 路线 section in now-context.
///
/// Mirrors styles.css `.sc-section-label` with the `.lhs.now` treatment and the
/// 此刻精選 AI region: left → sparkles + 「路線 · 此刻適合」(uppercase display,
/// sun-gold-deep), right → mono `AI · NOW` badge in fg-subtle.
struct RouteNowSectionHeader: View {
    var body: some View {
        HStack(alignment: .center) {
            HStack(spacing: 7) {
                Image(systemName: "sparkles")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(CT.sunGoldDeep)
                Text(NSLocalizedString("sheet.section.routes.now", comment: "路線 · 此刻適合 section header"))
                    .font(CT.display(11, .bold))
                    .tracking(1.3)
                    .textCase(.uppercase)
                    .foregroundStyle(CT.sunGoldDeep)
            }
            Spacer(minLength: 8)
            Text(verbatim: "AI · NOW")
                .font(CT.mono(11, .regular))
                .tracking(0.4)
                .foregroundStyle(CT.fgSubtle)
        }
        .padding(.horizontal, 4)
        .padding(.top, 6)
        .padding(.bottom, 2)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}

// MARK: - NearbySection

/// '附近' section rendered inside BottomInfoSheet when detent > .peek.
struct NearbySection: View {
    let experiences: [Experience]
    /// IDs of AI-ranked top picks (up to 3 pinned at top).
    let smartPickIds: [String]
    /// Reference coordinate for distance calculation (user location or map center).
    let referenceCoordinate: CLLocationCoordinate2D?
    let sortMode: SortMode
    /// Tapping a row jumps straight to the detail sheet.
    let onSelectExperience: (Experience) -> Void
    /// Long-pressing a row floats the quick preview card instead. Optional so
    /// callers that only wire a tap keep compiling.
    let onLongPressExperience: ((Experience) -> Void)?
    /// "问 Solo" context-menu action — opens a chat scoped to the experience.
    let onAskSoloExperience: ((Experience) -> Void)?
    /// When non-nil, passed through to EmptySheetListView to render the
    /// 'Explore another area' CTA that zooms the map out.
    let onExploreElsewhere: (() -> Void)?
    /// Suggested city name shown in the empty state when the current area has
    /// no experiences. Passed through to EmptySheetListView.
    let suggestedCityName: String?
    let onSwitchToSuggestedCity: (() -> Void)?

    @Environment(BestNowClock.self) private var clock
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(
        experiences: [Experience],
        smartPickIds: [String],
        referenceCoordinate: CLLocationCoordinate2D?,
        sortMode: SortMode = .smart,
        showsSectionDivider: Bool = false,
        onExploreElsewhere: (() -> Void)? = nil,
        suggestedCityName: String? = nil,
        onSwitchToSuggestedCity: (() -> Void)? = nil,
        onSelectExperience: @escaping (Experience) -> Void,
        onLongPressExperience: ((Experience) -> Void)? = nil,
        onAskSoloExperience: ((Experience) -> Void)? = nil
    ) {
        self.experiences = experiences
        self.smartPickIds = smartPickIds
        self.referenceCoordinate = referenceCoordinate
        self.sortMode = sortMode
        self.showsSectionDivider = showsSectionDivider
        self.onExploreElsewhere = onExploreElsewhere
        self.suggestedCityName = suggestedCityName
        self.onSwitchToSuggestedCity = onSwitchToSuggestedCity
        self.onSelectExperience = onSelectExperience
        self.onLongPressExperience = onLongPressExperience
        self.onAskSoloExperience = onAskSoloExperience
    }

    /// US-036: When true, the Nearby header is preceded by an inset divider so a
    /// clear visual break separates it from the Routes section above. Set false
    /// when Nearby is rendered standalone (no Routes section present).
    let showsSectionDivider: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // US-036: inset divider + localized "Nearby" header separates this
            // section from Routes above (showsDivider gated by composition).
            SheetSectionSeparator(titleKey: "sheet.section.nearby", showsDivider: showsSectionDivider)
            if experiences.isEmpty {
                // US-050: empty Nearby list. Announce on appear so VoiceOver
                // users learn the list is empty rather than thinking the sheet
                // froze; a visible row keeps the state legible to everyone.
                EmptySheetListView(
                    onExploreElsewhere: onExploreElsewhere,
                    suggestedCityName: suggestedCityName,
                    onSwitchToSuggestedCity: onSwitchToSuggestedCity
                )
            } else {
                // Each row now carries its own card chrome, so we separate them
                // with a 10pt gap (matching RoutesSection) rather than full-bleed
                // dividers — the list reads as a stack of discrete cards.
                //
                // No inner ScrollView: the host BottomInfoSheet wraps the whole
                // content closure in one ScrollView, so Nearby lays its rows out
                // inline as part of that single scroll stream. A nested ScrollView
                // here re-introduced the two-viewport conflict that hid this list
                // when the Routes section above grew long (and left the route cards
                // un-scrollable at mid). LazyVStack keeps rows lazily realized for
                // long lists.
                LazyVStack(spacing: 10) {
                    ForEach(sortedExperiences) { exp in
                        // Resolve the live "best now / closing soon" chip state for
                        // EVERY row from the shared clock — not just in Now sort.
                        // The chip is the app's most decision-relevant, perishable
                        // signal; hiding it in the distance/smart/soloScore sorts
                        // meant a traveler browsing by distance couldn't tell a
                        // nearby spot was in its golden hour (or closing in minutes)
                        // without opening it. A nil `minutesLeft` means "not best
                        // now", so the row keeps its plain form.
                        let chipState = BestNowChipState.resolve(for: exp, at: clock.tick)
                        let openNow = chipState.minutesLeft != nil
                        NearbyExperienceRow(
                            experience: exp,
                            isSmartPick: sortMode == .smart && smartPickIds.contains(exp.id),
                            distanceMeters: distance(to: exp),
                            isOpenNow: openNow,
                            bestNowChipState: openNow ? chipState : nil,
                            onTap: { onSelectExperience(exp) },
                            onLongPress: onLongPressExperience.map { handler in { handler(exp) } },
                            onAskSolo: onAskSoloExperience.map { handler in { handler(exp) } }
                        )
                    }
                }
                .animation(reduceMotion ? nil : .spring(response: 0.4, dampingFraction: 0.8), value: sortMode)
                .padding(.horizontal, 16)
                .padding(.top, 10)
                .padding(.bottom, 8)
            }
        }
        .padding(.top, 8)
    }

    private var sortedExperiences: [Experience] {
        switch sortMode {
        case .smart:
            let smartSet = Set(smartPickIds)
            let picks = smartPickIds.compactMap { id in experiences.first { $0.id == id } }
            let rest = experiences
                .filter { !smartSet.contains($0.id) }
                .sorted { distance(to: $0) ?? .infinity < distance(to: $1) ?? .infinity }
            return picks + rest
        case .distance:
            return experiences.sorted { distance(to: $0) ?? .infinity < distance(to: $1) ?? .infinity }
        case .soloScore:
            return experiences.sorted { $0.soloScore.overall > $1.soloScore.overall }
        case .now:
            let now = clock.tick
            return experiences.sorted { lhs, rhs in
                let lhsNow = isOpenNow(lhs, at: now)
                let rhsNow = isOpenNow(rhs, at: now)
                if lhsNow != rhsNow { return lhsNow }
                return distance(to: lhs) ?? .infinity < distance(to: rhs) ?? .infinity
            }
        }
    }

    /// True when `experience` is genuinely at its best at `date`.
    ///
    /// Uses `minutesLeftInBestWindow` (the same source the visible chip reads)
    /// rather than a bare "current hour ∈ bestTimes" check, so weekday- and
    /// season-scoped windows and midnight-wrapping windows are honored — a
    /// Saturday-only sunset window no longer floats to the top of the Now sort
    /// (or shows a "Best now" chip) on a weekday.
    private func isOpenNow(_ experience: Experience, at date: Date) -> Bool {
        experience.minutesLeftInBestWindow(at: date) != nil
    }

    private func distance(to experience: Experience) -> Double? {
        guard let ref = referenceCoordinate,
              let coord = experience.coordinate else { return nil }
        let from = CLLocation(latitude: ref.latitude, longitude: ref.longitude)
        let to = CLLocation(latitude: coord.latitude, longitude: coord.longitude)
        return from.distance(from: to)
    }
}

// MARK: - EmptySheetListView

/// US-050: Empty-state row for the BottomInfoSheet's Nearby list. When no
/// experiences are visible we show a localized message AND post a VoiceOver
/// announcement on appear, so VoiceOver users know the list is genuinely empty
/// instead of assuming the UI froze.
struct EmptySheetListView: View {
    /// Localized text used both for the on-screen label and the VoiceOver
    /// announcement. Exposed via the same key the test asserts on.
    static let announcementKey = "a11y.empty.nearby"

    /// When non-nil, renders an 'Explore another area' CTA that fires this
    /// callback on tap (after a selection haptic). Omit in previews / tests
    /// where no map action is wired up.
    var onExploreElsewhere: (() -> Void)? = nil

    /// When non-nil, shows a "Try [city]" CTA so users in empty cities can
    /// one-tap jump to a city that has seed data.
    var suggestedCityName: String? = nil
    var onSwitchToSuggestedCity: (() -> Void)? = nil

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var breathing = false

    var localizedEmptyText: String {
        NSLocalizedString(Self.announcementKey, comment: "Announced when the Nearby list is empty")
    }

    private var hasSuggestedCity: Bool {
        suggestedCityName != nil && onSwitchToSuggestedCity != nil
    }

    var body: some View {
        VStack(spacing: 16) {
            VStack(spacing: 8) {
                Image(systemName: "mappin.slash")
                    .font(.title2)
                    .foregroundStyle(.secondary)
                    .scaleEffect(breathing ? 1.08 : 1.0)
                    .opacity(breathing ? 0.7 : 1.0)
                Text(NSLocalizedString("empty.nearby.headline", comment: "Empty Nearby headline"))
                    .font(.headline)
                    .foregroundStyle(CT.fgPrimary)
                    .multilineTextAlignment(.center)
                if hasSuggestedCity {
                    Text(NSLocalizedString("empty.nearby.subtitle.nocity", comment: "Empty Nearby subtitle when city has no data"))
                        .font(.subheadline)
                        .foregroundStyle(CT.fgMuted)
                        .multilineTextAlignment(.center)
                } else {
                    Text(NSLocalizedString("empty.nearby.subtitle", comment: "Empty Nearby supporting subline"))
                        .font(.subheadline)
                        .foregroundStyle(CT.fgMuted)
                        .multilineTextAlignment(.center)
                }
            }

            VStack(spacing: 10) {
                if let cityName = suggestedCityName, let switchCity = onSwitchToSuggestedCity {
                    Button {
                        #if canImport(UIKit)
                        Haptics.impact(.medium)
                        #endif
                        switchCity()
                    } label: {
                        Label(
                            String(format: NSLocalizedString("empty.nearby.cta.city", comment: "CTA to switch to a city with data"), cityName),
                            systemImage: "airplane.departure"
                        )
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 20)
                        .padding(.vertical, 11)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(CT.accent)
                    .accessibilityHint(Text(String(format: NSLocalizedString("empty.nearby.a11y.city.hint", comment: "Accessibility hint for city switch CTA"), cityName)))
                }

                if let explore = onExploreElsewhere {
                    Button {
                        #if canImport(UIKit)
                        Haptics.selection()
                        #endif
                        explore()
                    } label: {
                        Label(
                            NSLocalizedString("empty.nearby.cta", comment: "CTA to zoom map out when Nearby list is empty"),
                            systemImage: "arrow.up.left.and.arrow.down.right"
                        )
                        .font(.subheadline.weight(.medium))
                        .padding(.horizontal, 16)
                        .padding(.vertical, 9)
                    }
                    .buttonStyle(.bordered)
                    .accessibilityHint(Text(NSLocalizedString("empty.nearby.cta", comment: "CTA to zoom map out when Nearby list is empty")))
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 32)
        .padding(.horizontal, 16)
        .accessibilityElement(children: .contain)
        .onAppear {
            #if canImport(UIKit)
            UIAccessibility.post(notification: .announcement, argument: localizedEmptyText)
            #endif
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 1.6).repeatForever(autoreverses: true)) {
                breathing = true
            }
        }
        .onChange(of: reduceMotion) { _, reduced in
            if reduced {
                withAnimation(.default) { breathing = false }
            } else {
                withAnimation(.easeInOut(duration: 1.6).repeatForever(autoreverses: true)) {
                    breathing = true
                }
            }
        }
    }
}

// MARK: - Preview

#Preview {
    ZStack(alignment: .bottom) {
        Color.teal.ignoresSafeArea()

        BottomInfoSheet(
            aiHint: NSLocalizedString("ai.now.hint", comment: "AI now hint"),
            count: 7,
            isNowMode: false,
            peekExperience: ExperienceService.hardcodedSeed.first,
            isSmartPick: true,
            referenceCoordinate: ExperienceService.hardcodedSeed.first?.coordinate
        ) { detent, _ in
            if detent != .peek {
                Text("Nearby list goes here")
                    .padding()
            }
        }
        .environment(BestNowClock.shared)
        .environment(LocationService.shared)
    }
}
