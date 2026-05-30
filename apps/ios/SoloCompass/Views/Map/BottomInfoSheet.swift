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
private let basePeekHeight: CGFloat = 170
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
    @State private var currentDetent: BottomSheetDetent = .peek
    @State private var dragOffset: CGFloat = 0
    @State private var isDragging: Bool = false
    @State var sortMode: SortMode = .smart
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private let aiHint: String
    private let count: Int
    private let isNowMode: Bool
    private let content: (BottomSheetDetent, Binding<SortMode>) -> Content

    public init(
        aiHint: String,
        count: Int,
        isNowMode: Bool,
        @ViewBuilder content: @escaping (BottomSheetDetent, Binding<SortMode>) -> Content
    ) {
        self.aiHint = aiHint
        self.count = count
        self.isNowMode = isNowMode
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
                NowHintRow(hint: aiHint)
                    .padding(.horizontal, 16)
                    .padding(.top, 6)
                SortCountToolbar(count: count, isNowMode: isNowMode, sortMode: $sortMode)
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                content(currentDetent, $sortMode)
                Spacer(minLength: 0)
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
        .animation(isDragging ? nil : .spring(response: 0.3, dampingFraction: 0.85), value: displayHeight)
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
                    isDragging = false
                    let projectedHeight = detentBaseHeight - value.predictedEndTranslation.height
                    let clampedHeight = max(scaledMinHeight, min(scaledMaxHeight, projectedHeight))
                    currentDetent = BottomSheetDetent.nearest(to: clampedHeight, traits: dynamicTypeTraits)
                    dragOffset = 0
                }
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(NSLocalizedString("sheet.handle", comment: "Bottom sheet drag handle")))
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

    var body: some View {
        HStack {
            sortButton
            Spacer()
            countBadge
        }
        .sheet(isPresented: $showSortSheet) {
            SortModeSheet(sortMode: $sortMode)
                .presentationDetents([.height(300)])
                .presentationDragIndicator(.visible)
        }
    }

    private var sortButton: some View {
        Button {
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
        .buttonStyle(.plain)
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

/// Single row in the '附近' section of the BottomInfoSheet.
/// Layout: 36×36 category disc | title + romanized + local | mono distance + compass arrow
struct NearbyExperienceRow: View {
    let experience: Experience
    let isSmartPick: Bool
    /// Distance in meters from the user's current location (or map center).
    let distanceMeters: Double?
    let onTap: () -> Void

    @State private var pressed = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let sunGold = Color(red: 1.0, green: 0.80, blue: 0.2)

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
            HStack(spacing: 10) {
                categoryDisc
                titleStack
                Spacer(minLength: 4)
                distancePill
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(rowBackground)
            .overlay(alignment: .leading) {
                if isSmartPick {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Self.sunGold)
                        .frame(width: 3)
                }
            }
        }
        .buttonStyle(.plain)
        .scaleEffect(pressed ? 0.86 : 1.0)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityHint(Text(NSLocalizedString("experience.card.hint", comment: "Double tap to view details")))
    }

    // MARK: - Sub-views

    private var categoryDisc: some View {
        ZStack {
            Circle()
                .fill(experience.category.color.opacity(0.18))
                .frame(width: 36, height: 36)
            Image(systemName: experience.category.symbol)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(experience.category.color)
        }
    }

    @ViewBuilder
    private var titleStack: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(experience.title)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.primary)
                .lineLimit(1)

            let sub = subtitleText
            if !sub.isEmpty {
                Text(sub)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
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

    private var distancePill: some View {
        HStack(spacing: 3) {
            if let meters = distanceMeters {
                Text(formattedDistance(meters))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            Image(systemName: "location.north.line.fill")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
    }

    @ViewBuilder
    private var rowBackground: some View {
        if isSmartPick {
            LinearGradient(
                colors: [
                    Self.sunGold.opacity(0.10),
                    Self.sunGold.opacity(0.04)
                ],
                startPoint: .leading,
                endPoint: .trailing
            )
        } else {
            Color.clear
        }
    }

    private var accessibilityLabel: Text {
        var label = experience.title
        if let meters = distanceMeters {
            label += ", \(formattedDistance(meters))"
        }
        if isSmartPick {
            label += ", " + NSLocalizedString("sheet.nearby.smartPick.a11y", comment: "AI pick")
        }
        return Text(label)
    }

    private func formattedDistance(_ meters: Double) -> String {
        if meters < 1000 {
            return String(format: "%dm", Int(meters))
        } else {
            return String(format: "%.1fkm", meters / 1000)
        }
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
        isNowFilter ? routes.filter(\.bestNow) : routes
    }

    var body: some View {
        let items = displayed
        Group {
            if !items.isEmpty {
                VStack(alignment: .leading, spacing: 0) {
                    // US-036: Routes is the first section, so its header omits the
                    // leading inset divider (the sheet must not open with a rule).
                    SheetSectionSeparator(titleKey: "sheet.section.routes", showsDivider: false)
                    Divider()
                        .padding(.horizontal, 16)
                    ForEach(items) { route in
                        Button { onSelectRoute(route) } label: {
                            RouteCard(route: route)
                        }
                        .buttonStyle(.plain)
                        if route.id != items.last?.id {
                            Divider()
                                .padding(.leading, 70)
                        }
                    }
                }
                .padding(.top, 8)
            }
        }
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
    let onSelectExperience: (Experience) -> Void
    /// When non-nil, passed through to EmptySheetListView to render the
    /// 'Explore another area' CTA that zooms the map out.
    let onExploreElsewhere: (() -> Void)?

    init(
        experiences: [Experience],
        smartPickIds: [String],
        referenceCoordinate: CLLocationCoordinate2D?,
        sortMode: SortMode = .smart,
        showsSectionDivider: Bool = false,
        onExploreElsewhere: (() -> Void)? = nil,
        onSelectExperience: @escaping (Experience) -> Void
    ) {
        self.experiences = experiences
        self.smartPickIds = smartPickIds
        self.referenceCoordinate = referenceCoordinate
        self.sortMode = sortMode
        self.showsSectionDivider = showsSectionDivider
        self.onExploreElsewhere = onExploreElsewhere
        self.onSelectExperience = onSelectExperience
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
            Divider()
                .padding(.horizontal, 16)
            if experiences.isEmpty {
                // US-050: empty Nearby list. Announce on appear so VoiceOver
                // users learn the list is empty rather than thinking the sheet
                // froze; a visible row keeps the state legible to everyone.
                EmptySheetListView(onExploreElsewhere: onExploreElsewhere)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(sortedExperiences) { exp in
                            NearbyExperienceRow(
                                experience: exp,
                                isSmartPick: sortMode == .smart && smartPickIds.contains(exp.id),
                                distanceMeters: distance(to: exp),
                                onTap: { onSelectExperience(exp) }
                            )
                            Divider()
                                .padding(.leading, 62)
                        }
                    }
                }
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
            let hour = Calendar.current.component(.hour, from: Date())
            return experiences.sorted { lhs, rhs in
                let lhsNow = lhs.bestTimes.contains { $0.contains(hour: hour) }
                let rhsNow = rhs.bestTimes.contains { $0.contains(hour: hour) }
                if lhsNow != rhsNow { return lhsNow }
                return distance(to: lhs) ?? .infinity < distance(to: rhs) ?? .infinity
            }
        }
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

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var breathing = false

    var localizedEmptyText: String {
        NSLocalizedString(Self.announcementKey, comment: "Announced when the Nearby list is empty")
    }

    var body: some View {
        VStack(spacing: 16) {
            VStack(spacing: 8) {
                Image(systemName: "mappin.slash")
                    .font(.title2)
                    .foregroundStyle(.secondary)
                    .scaleEffect(breathing ? 1.08 : 1.0)
                    .opacity(breathing ? 0.7 : 1.0)
                Text(localizedEmptyText)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
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
            isNowMode: false
        ) { detent, _ in
            if detent != .peek {
                Text("Nearby list goes here")
                    .padding()
            }
        }
        .environment(BestNowClock.shared)
    }
}
