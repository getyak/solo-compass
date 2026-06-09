import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

/// Top-of-screen pill bar. One tap, clear feedback. The whole bar slides in
/// over the map; we keep it visually light so the map stays the protagonist.
public struct FilterBarView: View {
    let selectedCategory: ExperienceCategory?
    let isNowSelected: Bool
    /// Currently-selected custom tag pill (mirrors `MapViewModel.selectedCustomTag`).
    /// nil when no custom tag is active. US-008.
    let selectedCustomTag: String?
    /// True when the "Saved" filter is active (mirrors `MapViewModel.isFavoriteFilter`).
    let isFavoriteSelected: Bool
    let onSelectNow: () -> Void
    let onSelectAll: () -> Void
    /// Tap handler for the "Saved" pill — shows only favourited experiences.
    let onSelectFavorite: () -> Void
    /// Called when the user re-taps an already-active pill to deselect it back to 'All'.
    let onClear: () -> Void
    let onSelectCategory: (ExperienceCategory) -> Void
    /// Tap handler for one of the user-defined `customTags` pills. US-008.
    let onSelectCustomTag: (String) -> Void
    /// Driven by the parent when the map camera is moving; triggers fade+shrink.
    @Binding var isMapPanning: Bool
    /// Number of experiences currently visible on the map. Used to render the
    /// count badge on the selected pill. Defaults to 0 for previews/back-compat.
    let resultCount: Int
    /// How many visible experiences are currently at their best time.
    let nowCount: Int

    /// Namespace for the shared gliding selection highlight.
    @Namespace private var pillHighlight

    /// US-034: width of the scrolling pill content and of the visible viewport.
    /// When content overflows the viewport we paint a right-edge fade so users
    /// get a visual hint that more categories are scrollable off-screen.
    @State private var contentWidth: CGFloat = 0
    @State private var viewportWidth: CGFloat = 0

    /// User's chosen subset of categories. Injected via SwiftUI environment
    /// (US-006). Previews/tests that don't supply preferences get a freshly
    /// constructed `UserPreferences`, which defaults to all 8 categories.
    @Environment(UserPreferences.self) private var preferences
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isPulsing: Bool = false
    @State private var nowCountPop: Bool = false
    @State private var lastNowCount: Int = 0
    @State private var heartPulse: Bool = false
    @State private var didCelebrateSaved: Bool = false
    @State private var lastResultCount: Int = 0
    @State private var emptyShake: Int = 0

    /// Routes a pill tap to either deselect (toggle-off) or select, with distinct haptics.
    /// When `isSelected` is true the active pill is tapped again — call `onClear` with a
    /// light-impact (deselect) haptic. Otherwise call `select` with a selection haptic.
    private func handleTap(isSelected: Bool, select: () -> Void) {
        if isSelected {
            Haptics.impact(.light)
            onClear()
        } else {
            Haptics.selection()
            select()
        }
    }

    /// Pure helper: returns true when a tap on a pill with `isSelected` state should
    /// resolve to a clear (toggle-off) rather than a selection. Used in unit tests.
    static func resolvesToClear(isSelected: Bool) -> Bool { isSelected }

    /// Called when `nowCount` changes. Fires a spring scale-pop + gold flash + selection
    /// haptic only when the count increases (a place enters its golden window). Decreases
    /// are silent so the pill never feels noisy. Respects reduceMotion: skips scale/flash
    /// but still fires the haptic (tactile feedback remains useful without motion).
    private func handleNowCountChange(_ old: Int, _ new: Int) {
        lastNowCount = new
        guard new > old else { return }
        #if canImport(UIKit)
        Haptics.selection()
        #endif
        guard !reduceMotion else { return }
        withAnimation(.spring(response: 0.3, dampingFraction: 0.5)) {
            nowCountPop = true
        }
        Task {
            try? await Task.sleep(nanoseconds: 500_000_000)
            withAnimation(.easeOut(duration: 0.25)) {
                nowCountPop = false
            }
        }
    }

    public init(
        selectedCategory: ExperienceCategory?,
        isNowSelected: Bool,
        selectedCustomTag: String? = nil,
        isFavoriteSelected: Bool = false,
        nowCount: Int = 0,
        onSelectNow: @escaping () -> Void,
        onSelectAll: @escaping () -> Void,
        onSelectFavorite: @escaping () -> Void = {},
        onClear: @escaping () -> Void = {},
        onSelectCategory: @escaping (ExperienceCategory) -> Void,
        onSelectCustomTag: @escaping (String) -> Void = { _ in },
        isMapPanning: Binding<Bool> = .constant(false),
        resultCount: Int = 0
    ) {
        self.selectedCategory = selectedCategory
        self.isNowSelected = isNowSelected
        self.selectedCustomTag = selectedCustomTag
        self.isFavoriteSelected = isFavoriteSelected
        self.nowCount = nowCount
        self.onSelectNow = onSelectNow
        self.onSelectAll = onSelectAll
        self.onSelectFavorite = onSelectFavorite
        self.onClear = onClear
        self.onSelectCategory = onSelectCategory
        self.onSelectCustomTag = onSelectCustomTag
        self._isMapPanning = isMapPanning
        self.resultCount = resultCount
    }

    /// Stable string ID for the currently selected pill — drives matchedGeometryEffect.
    private var selectionID: String {
        if isNowSelected { return "now" }
        if isFavoriteSelected { return "saved" }
        if let tag = selectedCustomTag { return "tag-\(tag)" }
        if let cat = selectedCategory { return cat.rawValue }
        return "all"
    }

    /// Iterate `allCases` (not the `Set`) so pill order stays stable and
    /// matches enum declaration order.
    private var visibleCategories: [ExperienceCategory] {
        Self.visiblePills(from: preferences.visibleCategories)
    }

    /// Pure helper: returns true when a filter is active and the result count
    /// transitions from a positive value to zero — the signal to fire the
    /// empty-state shake + warning haptic. Unit-testable without UI state.
    static func resolvesToEmpty(filterActive: Bool, oldCount: Int, newCount: Int) -> Bool {
        filterActive && oldCount > 0 && newCount == 0
    }

    /// Pure function exposed for unit testing — keeps pill ordering tied to
    /// `ExperienceCategory.allCases` and filters by the user's chosen set.
    static func visiblePills(from selection: Set<ExperienceCategory>) -> [ExperienceCategory] {
        ExperienceCategory.allCases.filter { selection.contains($0) }
    }

    /// US-034: width tolerance (pt) below which we treat content + viewport as
    /// equal — sub-pixel layout rounding shouldn't trigger a spurious fade.
    static let overflowTolerance: CGFloat = 1.0

    /// Clamps a count for display in a pill badge to prevent 3-digit values from
    /// overflowing the single-line pill bar layout.
    static func compactCount(_ n: Int) -> String { n > 99 ? "99+" : "\(n)" }

    /// Pure, testable overflow predicate driving the right-edge scroll fade.
    /// Returns true only when the pill content is meaningfully wider than the
    /// visible viewport (i.e. some chips are off-screen to the right). A zero
    /// width (not yet laid out) never shows the affordance.
    static func shouldShowScrollAffordance(contentWidth: CGFloat, viewportWidth: CGFloat) -> Bool {
        guard contentWidth > 0, viewportWidth > 0 else { return false }
        return contentWidth - viewportWidth > overflowTolerance
    }

    /// Instance accessor used by `body` — bridges the measured @State widths to
    /// the pure predicate above.
    private var isOverflowing: Bool {
        Self.shouldShowScrollAffordance(contentWidth: contentWidth, viewportWidth: viewportWidth)
    }

    public var body: some View {
        GlassmorphismCapsule(horizontalPadding: 0, verticalPadding: 0) {
            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        nowPill(isSelected: isNowSelected, action: onSelectNow)
                            .id("now")
                        pill(
                            id: "all",
                            label: NSLocalizedString("filter.all", comment: "All"),
                            isSelected: !isNowSelected && selectedCategory == nil && selectedCustomTag == nil,
                            // Use the shared brown selected-fill (same as Now and
                            // category chips) so the active 'All' filter carries
                            // real visual weight. The old Color.primary fill was
                            // near-invisible on the dark glass bar — the currently
                            // active filter read as the least prominent chip.
                            color: Self.selectedFill,
                            action: onSelectAll
                        )
                        .id("all")
                        favoritePill(isSelected: isFavoriteSelected, action: onSelectFavorite)
                            .id("saved")
                        ForEach(visibleCategories) { category in
                            iconPill(
                                category: category,
                                isSelected: selectionID == category.rawValue,
                                action: { onSelectCategory(category) }
                            )
                            .id(category.rawValue)
                        }
                        // US-041: index as stable id so duplicate custom tags don't
                        // collapse into a single row (`id: \.self` dedups on value).
                        ForEach(Array(preferences.customTags.enumerated()), id: \.offset) { _, tag in
                            customTagPill(
                                tag: tag,
                                isSelected: selectionID == "tag-\(tag)",
                                action: { onSelectCustomTag(tag) }
                            )
                            .id("tag-\(tag)")
                        }
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 5)
                    .animation(.spring(response: 0.4, dampingFraction: 0.75), value: selectionID)
                }
                // A horizontal ScrollView places no bound on its own vertical
                // extent, so inside the top overlay's VStack (filter bar above a
                // Spacer) it greedily stretched to fill all remaining height. The
                // GlassmorphismCapsule's `.background(in: Capsule())` then tracked
                // that full-height frame, rendering the glass as a giant vertical
                // capsule arching across the map — the dark "arch" scrim that
                // covered the home screen. Pinning the scroll view to its content's
                // intrinsic height keeps the bar one pill-row tall.
                .fixedSize(horizontal: false, vertical: true)
                .onAppear {
                    proxy.scrollTo(selectionID, anchor: .center)
                }
                .onChange(of: selectionID) { _, id in
                    withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.3)) {
                        proxy.scrollTo(id, anchor: .center)
                    }
                }
                // US-034: measure the laid-out pill content width.
                .background(
                    GeometryReader { proxy in
                        Color.clear.preference(key: FilterContentWidthKey.self, value: proxy.size.width)
                    }
                )
            }
            // US-034: measure the visible viewport width so we can compare it
            // against the content width and only fade when chips overflow.
            .background(
                GeometryReader { proxy in
                    Color.clear.preference(key: FilterViewportWidthKey.self, value: proxy.size.width)
                }
            )
            .onPreferenceChange(FilterContentWidthKey.self) { contentWidth = $0 }
            .onPreferenceChange(FilterViewportWidthKey.self) { viewportWidth = $0 }
            // US-034: right-edge fade. Only masks when content overflows; when
            // every chip fits, the mask is a solid (fully opaque) rectangle so
            // nothing is clipped.
            .mask(scrollAffordanceMask)
        }
        .modifier(ShakeEffect(animatableData: CGFloat(emptyShake)))
        .padding(.horizontal, 16)
        .opacity(isMapPanning ? 0.4 : 1.0)
        .scaleEffect(isMapPanning ? 0.85 : 1.0)
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: isMapPanning)
        .onTapGesture { isMapPanning = false }
        // US-050: when the active filter yields no results, announce it so
        // VoiceOver users know the empty map isn't a frozen UI. Fires both on
        // first appearance and whenever the count transitions to zero.
        .onAppear { announceIfEmpty(resultCount) }
        .onChange(of: resultCount) { _, newCount in announceIfEmpty(newCount) }
        .onChange(of: resultCount) { old, new in
            let filterActive = isNowSelected || isFavoriteSelected || selectedCategory != nil || selectedCustomTag != nil
            if new > old && filterActive && !reduceMotion {
                #if canImport(UIKit)
                Haptics.selection()
                #endif
            }
            if Self.resolvesToEmpty(filterActive: filterActive, oldCount: old, newCount: new) {
                #if canImport(UIKit)
                Haptics.notify(.warning)
                #endif
                if !reduceMotion {
                    withAnimation(.default) { emptyShake += 1 }
                }
            }
            lastResultCount = new
        }
    }

    /// US-050: localized VoiceOver string posted when the filter has no results.
    static let emptyResultsAnnouncementKey = "a11y.empty.filterResults"

    var localizedEmptyText: String {
        NSLocalizedString(Self.emptyResultsAnnouncementKey, comment: "Announced when a filter returns no results")
    }

    /// Posts a VoiceOver announcement when `count` is zero. No-op otherwise so
    /// non-empty filters don't chatter.
    private func announceIfEmpty(_ count: Int) {
        guard count == 0 else { return }
        #if canImport(UIKit)
        UIAccessibility.post(notification: .announcement, argument: localizedEmptyText)
        #endif
    }

    /// US-034: gradient mask that fades the trailing ~24pt of the strip when
    /// content overflows; otherwise an opaque rectangle (no visible change).
    @ViewBuilder
    private var scrollAffordanceMask: some View {
        if isOverflowing {
            LinearGradient(
                stops: [
                    .init(color: .black, location: 0),
                    .init(color: .black, location: 0.88),
                    .init(color: .black.opacity(0), location: 1.0)
                ],
                startPoint: .leading,
                endPoint: .trailing
            )
        } else {
            Rectangle()
        }
    }

    /// Selected-pill fill. US-028: replaced the old #D4A843 gold (which gave
    /// only ~1.9:1 against the white pill text) with CT.accent (#5D3000). White
    /// text on this brown clears WCAG AA/AAA at ≥ 7:1.
    static let selectedFillRGB: (r: Int, g: Int, b: Int) = (0x5D, 0x30, 0x00)
    /// Selected-pill foreground — white, used for the text/glyph on the fill.
    static let selectedForegroundRGB: (r: Int, g: Int, b: Int) = (0xFF, 0xFF, 0xFF)
    private static let selectedFill = Color(
        red: Double(selectedFillRGB.r) / 255,
        green: Double(selectedFillRGB.g) / 255,
        blue: Double(selectedFillRGB.b) / 255
    )

    private func nowPill(isSelected: Bool, action: @escaping () -> Void) -> some View {
        let label = NSLocalizedString("filter.now", comment: "Now")
        let a11yLabel: String = nowCount > 0
            ? String(format: NSLocalizedString("filter.now.a11y", comment: "Now, n experiences at their best"), nowCount)
            : label

        return Button {
            handleTap(isSelected: isSelected, select: action)
        } label: {
            HStack(spacing: 5) {
                Circle()
                    .fill(isSelected ? Color.white : CT.sunGold)
                    .frame(width: 6, height: 6)
                    .scaleEffect(isPulsing ? 1.4 : 1.0)
                    .opacity(isPulsing ? 0.5 : 1.0)

                Text(label)
                    .font(.subheadline.weight(.medium))

                if nowCount > 0 {
                    ZStack {
                        Text(Self.compactCount(nowCount))
                            .font(.caption2.monospacedDigit().weight(.semibold))
                            .contentTransition(.numericText(value: Double(nowCount)))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(
                                Capsule().fill(isSelected ? Color.white.opacity(0.28) : CT.sunGold.opacity(0.2))
                            )
                        // Gold flash overlay — fades in on increase, eases out
                        Capsule()
                            .fill(CT.sunGold.opacity(nowCountPop ? 0.6 : 0))
                            .animation(.easeOut(duration: 0.5), value: nowCountPop)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                    }
                    .scaleEffect(nowCountPop ? 1.35 : 1.0)
                    .animation(.spring(response: 0.3, dampingFraction: 0.5), value: nowCountPop)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .foregroundStyle(isSelected ? .white : CT.accent)
            .background {
                if isSelected {
                    Capsule()
                        .fill(Self.selectedFill)
                        .matchedGeometryEffect(id: "filterHighlight", in: pillHighlight)
                }
            }
            .overlay(
                Capsule().stroke(isSelected ? Color.clear : CT.sunGold, lineWidth: 1)
            )
            .overlay(alignment: .topTrailing) {
                if isSelected && resultCount > 0 {
                    countBadge(count: resultCount, tint: Self.selectedFill)
                        .offset(x: 6, y: -6)
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .animation(.spring(response: 0.3, dampingFraction: 0.65), value: resultCount)
        }
        .buttonStyle(PressableButtonStyle())
        .accessibilityLabel(Text(a11yLabel))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityValue(isSelected && resultCount > 0 ? Text("\(resultCount) results") : Text(""))
        .accessibilityHint(isSelected ? Text(NSLocalizedString("filter.pill.clear.hint", comment: "Double tap to clear this filter")) : Text(""))
        .onAppear {
            lastNowCount = nowCount
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) {
                isPulsing = true
            }
        }
        .onChange(of: reduceMotion) { _, reduced in
            if reduced {
                withAnimation(.default) { isPulsing = false }
            } else {
                withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) {
                    isPulsing = true
                }
            }
        }
        .onChange(of: nowCount) { old, new in handleNowCountChange(old, new) }
    }

    private func pill(id: String, label: String, isSelected: Bool, color: Color, action: @escaping () -> Void) -> some View {
        Button {
            handleTap(isSelected: isSelected, select: action)
        } label: {
            HStack(spacing: 5) {
                Text(label)
                    .font(.subheadline.weight(.medium))

                // Inline result count — mirrors the Now pill's inline badge so
                // every filter chip speaks one visual language. Replaces the old
                // floating topTrailing badge, which read as a stray dot hovering
                // off the chip's corner.
                if isSelected && resultCount > 0 {
                    Text(Self.compactCount(resultCount))
                        .font(.caption2.monospacedDigit().weight(.semibold))
                        .contentTransition(reduceMotion ? .identity : .numericText(value: Double(resultCount)))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(Color.white.opacity(0.28)))
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .foregroundStyle(isSelected ? .white : .primary)
            .background {
                if isSelected {
                    Capsule()
                        .fill(color)
                        .matchedGeometryEffect(id: "filterHighlight", in: pillHighlight)
                }
            }
            .overlay(
                Capsule().stroke(isSelected ? Color.clear : Color.primary.opacity(0.2), lineWidth: 1)
            )
            .animation(.spring(response: 0.3, dampingFraction: 0.65), value: resultCount)
        }
        .buttonStyle(PressableButtonStyle())
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityValue(isSelected && resultCount > 0 ? Text("\(resultCount) results") : Text(""))
    }

    /// "Saved" pill — a heart glyph + localized label that filters the map to
    /// the user's favourited experiences. It toggles (the parent's
    /// `onSelectFavorite` flips `isFavoriteFilter`), so we always route taps to
    /// `action` rather than the All-reverting `onClear` path. Selected state uses
    /// a warm red fill that matches the heart-favourite affordance elsewhere in
    /// the app; the inline count mirrors the All/Now chips' visual language.
    private func favoritePill(isSelected: Bool, action: @escaping () -> Void) -> some View {
        let label = NSLocalizedString("filter.saved", comment: "Saved (favourites filter)")
        let tint = Color(red: 0xE0/255, green: 0x3A/255, blue: 0x3A/255)
        return Button {
            if !isSelected && resultCount > 0 {
                if !didCelebrateSaved {
                    #if canImport(UIKit)
                    Haptics.notify(.success)
                    #endif
                    didCelebrateSaved = true
                    if !reduceMotion {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.5)) {
                            heartPulse = true
                        }
                        Task {
                            try? await Task.sleep(nanoseconds: 450_000_000)
                            withAnimation(.easeOut(duration: 0.2)) {
                                heartPulse = false
                            }
                        }
                    }
                } else {
                    #if canImport(UIKit)
                    Haptics.selection()
                    #endif
                }
            } else if isSelected {
                #if canImport(UIKit)
                Haptics.impact(.light)
                #endif
            } else {
                #if canImport(UIKit)
                Haptics.selection()
                #endif
            }
            action()
        } label: {
            HStack(spacing: 5) {
                Image(systemName: isSelected ? "heart.fill" : "heart")
                    .font(.caption.weight(.semibold))
                    .scaleEffect(heartPulse ? 1.35 : 1.0)
                    .animation(.spring(response: 0.3, dampingFraction: 0.5), value: heartPulse)

                Text(label)
                    .font(.subheadline.weight(.medium))

                if isSelected && resultCount > 0 {
                    Text(Self.compactCount(resultCount))
                        .font(.caption2.monospacedDigit().weight(.semibold))
                        .contentTransition(reduceMotion ? .identity : .numericText(value: Double(resultCount)))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(Color.white.opacity(0.28)))
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .foregroundStyle(isSelected ? .white : tint)
            .background {
                if isSelected {
                    Capsule()
                        .fill(tint)
                        .matchedGeometryEffect(id: "filterHighlight", in: pillHighlight)
                }
            }
            .overlay(
                Capsule().stroke(isSelected ? Color.clear : tint.opacity(0.7), lineWidth: 1)
            )
            .animation(.spring(response: 0.3, dampingFraction: 0.65), value: resultCount)
        }
        .buttonStyle(PressableButtonStyle())
        .accessibilityLabel(Text(label))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityValue(isSelected && resultCount > 0 ? Text("\(resultCount) results") : Text(""))
    }

    private func iconPill(category: ExperienceCategory, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button {
            handleTap(isSelected: isSelected, select: action)
        } label: {
            Image(systemName: category.symbol)
                .font(.body.weight(.semibold))
                .frame(width: 34, height: 34)
                .foregroundStyle(isSelected ? .white : category.color)
                .background {
                    if isSelected {
                        Circle()
                            .fill(category.color)
                            .matchedGeometryEffect(id: "filterHighlight", in: pillHighlight)
                    }
                }
                .overlay(
                    Circle().stroke(isSelected ? Color.clear : category.color, lineWidth: 1)
                )
                .overlay(alignment: .topTrailing) {
                    if isSelected && resultCount > 0 {
                        countBadge(count: resultCount, tint: category.color)
                            .offset(x: 6, y: -6)
                            .transition(.scale.combined(with: .opacity))
                    }
                }
                .animation(.spring(response: 0.3, dampingFraction: 0.65), value: resultCount)
                // US-019: keep the visible chip 36×36 but expand the tappable
                // region to the 44pt HIG minimum.
                .frame(
                    minWidth: HitTargetMetrics.minimum,
                    minHeight: HitTargetMetrics.minimum
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(PressableButtonStyle())
        .accessibilityLabel(Text(category.localizedTitle))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityValue(isSelected && resultCount > 0 ? Text("\(resultCount) results") : Text(""))
        .accessibilityHint(isSelected ? Text(NSLocalizedString("filter.pill.clear.hint", comment: "Double tap to clear this filter")) : Text(""))
    }

    /// Pill rendered for each entry in `UserPreferences.customTags`. Same
    /// shape as `iconPill` (36×36 circle, tag.fill glyph, accent color), so
    /// it visually reads as part of the same filter row. US-008.
    private func customTagPill(tag: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button {
            handleTap(isSelected: isSelected, select: action)
        } label: {
            Image(systemName: "tag.fill")
                .font(.body.weight(.semibold))
                .frame(width: 36, height: 36)
                .foregroundStyle(isSelected ? .white : Color.accentColor)
                .background {
                    if isSelected {
                        Circle()
                            .fill(Color.accentColor)
                            .matchedGeometryEffect(id: "filterHighlight", in: pillHighlight)
                    }
                }
                .overlay(
                    Circle().stroke(isSelected ? Color.clear : Color.accentColor.opacity(0.4), lineWidth: 1)
                )
                .overlay(alignment: .topTrailing) {
                    if isSelected && resultCount > 0 {
                        countBadge(count: resultCount, tint: .accentColor)
                            .offset(x: 6, y: -6)
                            .transition(.scale.combined(with: .opacity))
                    }
                }
                .animation(.spring(response: 0.3, dampingFraction: 0.65), value: resultCount)
        }
        .buttonStyle(PressableButtonStyle())
        .accessibilityLabel(Text(tag))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityValue(isSelected && resultCount > 0 ? Text("\(resultCount) results") : Text(""))
        .accessibilityHint(isSelected ? Text(NSLocalizedString("filter.pill.clear.hint", comment: "Double tap to clear this filter")) : Text(""))
    }

    @ViewBuilder
    private func countBadge(count: Int, tint: Color) -> some View {
        Text(Self.compactCount(count))
            .font(.caption2.weight(.semibold).monospacedDigit())
            .contentTransition(reduceMotion ? .identity : .numericText(value: Double(count)))
            .foregroundStyle(.white)
            .padding(.horizontal, 5)
            .frame(minWidth: 16, minHeight: 16)
            .background(Capsule().fill(tint))
    }
}

// MARK: - ShakeEffect

/// Damped 3-cycle horizontal sine that maps integer counter increments to a
/// brief left-right head-shake — used by FilterBarView's empty-filter feedback.
private struct ShakeEffect: GeometryEffect {
    var animatableData: CGFloat

    func effectValue(size: CGSize) -> ProjectionTransform {
        // Each integer bump in animatableData drives one full shake cycle.
        // The fractional part of animatableData is what SwiftUI animates
        // between 0→1. We map that to 3 sine oscillations with exponential
        // damping so the wobble fades naturally without needing a Task delay.
        let phase = animatableData - floor(animatableData)
        let amplitude: CGFloat = 6
        let cycles: CGFloat = 3
        let damping = 1 - phase          // fades to zero by phase == 1
        let dx = amplitude * damping * sin(phase * cycles * 2 * .pi)
        return ProjectionTransform(CGAffineTransform(translationX: dx, y: 0))
    }
}

// MARK: - Scroll affordance preference keys (US-034)

/// Width of the scrolling pill HStack content.
private struct FilterContentWidthKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

/// Width of the visible ScrollView viewport.
private struct FilterViewportWidthKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

// MARK: - PressableButtonStyle moved to Views/Shared/PressableButtonStyle.swift
// (shared with ChatInputBar to avoid duplication)

#Preview {
    VStack {
        FilterBarView(
            selectedCategory: .coffee,
            isNowSelected: false,
            nowCount: 0,
            onSelectNow: {},
            onSelectAll: {},
            onSelectCategory: { _ in }
        )
        FilterBarView(
            selectedCategory: nil,
            isNowSelected: true,
            nowCount: 7,
            onSelectNow: {},
            onSelectAll: {},
            onSelectCategory: { _ in }
        )
        FilterBarView(
            selectedCategory: nil,
            isNowSelected: false,
            nowCount: 3,
            onSelectNow: {},
            onSelectAll: {},
            onSelectCategory: { _ in }
        )
    }
    .padding(.vertical)
    .background(Color(red: 0xF5/255, green: 0xF0/255, blue: 0xE8/255))
    .environment(UserPreferences())
}

#Preview("First-save celebration") {
    struct FirstSaveDemo: View {
        @State private var isFavoriteSelected = false
        @State private var favoriteCount = 3
        var body: some View {
            VStack(spacing: 16) {
                FilterBarView(
                    selectedCategory: nil,
                    isNowSelected: false,
                    isFavoriteSelected: isFavoriteSelected,
                    nowCount: 0,
                    onSelectNow: {},
                    onSelectAll: {},
                    onSelectFavorite: { isFavoriteSelected.toggle() },
                    onClear: { isFavoriteSelected = false },
                    onSelectCategory: { _ in },
                    resultCount: isFavoriteSelected ? favoriteCount : 0
                )
                Text(isFavoriteSelected ? "Saved filter active (\(favoriteCount) results)" : "Tap Saved to trigger first-save celebration")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button("Reset celebration state") {
                    isFavoriteSelected = false
                }
                .buttonStyle(.bordered)
            }
            .padding()
            .background(Color(red: 0xF5/255, green: 0xF0/255, blue: 0xE8/255))
            .environment(UserPreferences())
        }
    }
    return FirstSaveDemo()
}

#Preview("Now count pop demo") {
    struct NowCountDemo: View {
        @State private var nowCount = 2
        var body: some View {
            VStack(spacing: 16) {
                FilterBarView(
                    selectedCategory: nil,
                    isNowSelected: false,
                    nowCount: nowCount,
                    onSelectNow: {},
                    onSelectAll: {},
                    onSelectCategory: { _ in }
                )
                Button("Add a best-now place (+1)") { nowCount += 1 }
                    .buttonStyle(.borderedProminent)
                Button("Remove a best-now place (-1)") { if nowCount > 0 { nowCount -= 1 } }
                    .buttonStyle(.bordered)
                Text("nowCount: \(nowCount)")
                    .font(.caption.monospacedDigit())
            }
            .padding()
            .background(Color(red: 0xF5/255, green: 0xF0/255, blue: 0xE8/255))
            .environment(UserPreferences())
        }
    }
    return NowCountDemo()
}
