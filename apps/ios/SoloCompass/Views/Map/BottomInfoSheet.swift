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
    private let onRefresh: (() async -> Void)?
    private let content: (BottomSheetDetent, Binding<SortMode>) -> Content

    public init(
        aiHint: String,
        count: Int,
        isNowMode: Bool,
        peekExperience: Experience? = nil,
        isSmartPick: Bool = false,
        referenceCoordinate: CLLocationCoordinate2D? = nil,
        isPreviewActive: Bool = false,
        onRefresh: (() async -> Void)? = nil,
        @ViewBuilder content: @escaping (BottomSheetDetent, Binding<SortMode>) -> Content
    ) {
        self.aiHint = aiHint
        self.count = count
        self.isNowMode = isNowMode
        self.peekExperience = peekExperience
        self.isSmartPick = isSmartPick
        self.referenceCoordinate = referenceCoordinate
        self.isPreviewActive = isPreviewActive
        self.onRefresh = onRefresh
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
                        .padding(.bottom, 28 * BottomSheetDetentScale.factor())
                }
                // Freeze the ScrollView while the handle is being dragged. The
                // sheet height animates every frame during a settle; an active
                // ScrollView would re-clamp its contentOffset against that moving
                // viewport and fight the drag, producing flicker. Re-enabled the
                // instant the drag ends.
                .refreshable {
                    if let onRefresh { await onRefresh() }
                }
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
        } else if isNowMode {
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
            if isNowMode {
                peekHeaderLabel
            }
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

    private var relativeTimeLabel: String {
        let components = Calendar.current.dateComponents([.minute], from: clock.tick, to: Date())
        let minutes = abs(components.minute ?? 0)
        if minutes < 1 {
            return NSLocalizedString("now.time.justNow", comment: "Updated just now")
        } else if minutes < 5 {
            return NSLocalizedString("now.time.recent", comment: "Updated recently")
        } else {
            return String(
                format: NSLocalizedString("now.time.minutesAgo", comment: "Updated N minutes ago"),
                minutes
            )
        }
    }

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "sunset.fill")
                .font(.caption)
                .foregroundStyle(.orange)
            Text(hint)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .minimumScaleFactor(0.85)
            Spacer(minLength: 4)
            Text(relativeTimeLabel)
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text("\(hint), \(relativeTimeLabel)"))
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
                VStack(alignment: .leading, spacing: 1) {
                    Text(sortMode.localizedTitle)
                        .font(.caption.weight(.medium))
                    Text(NSLocalizedString(sortMode.subtitleKey, comment: "Sort mode subtitle"))
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                }
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
