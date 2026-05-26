import SwiftUI

/// Top-of-screen pill bar. One tap, clear feedback. The whole bar slides in
/// over the map; we keep it visually light so the map stays the protagonist.
public struct FilterBarView: View {
    let selectedCategory: ExperienceCategory?
    let isNowSelected: Bool
    /// Currently-selected custom tag pill (mirrors `MapViewModel.selectedCustomTag`).
    /// nil when no custom tag is active. US-008.
    let selectedCustomTag: String?
    let onSelectNow: () -> Void
    let onSelectAll: () -> Void
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

    /// User's chosen subset of categories. Injected via SwiftUI environment
    /// (US-006). Previews/tests that don't supply preferences get a freshly
    /// constructed `UserPreferences`, which defaults to all 8 categories.
    @Environment(UserPreferences.self) private var preferences
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isPulsing: Bool = false

    public init(
        selectedCategory: ExperienceCategory?,
        isNowSelected: Bool,
        selectedCustomTag: String? = nil,
        nowCount: Int = 0,
        onSelectNow: @escaping () -> Void,
        onSelectAll: @escaping () -> Void,
        onSelectCategory: @escaping (ExperienceCategory) -> Void,
        onSelectCustomTag: @escaping (String) -> Void = { _ in },
        isMapPanning: Binding<Bool> = .constant(false),
        resultCount: Int = 0
    ) {
        self.selectedCategory = selectedCategory
        self.isNowSelected = isNowSelected
        self.selectedCustomTag = selectedCustomTag
        self.nowCount = nowCount
        self.onSelectNow = onSelectNow
        self.onSelectAll = onSelectAll
        self.onSelectCategory = onSelectCategory
        self.onSelectCustomTag = onSelectCustomTag
        self._isMapPanning = isMapPanning
        self.resultCount = resultCount
    }

    /// Stable string ID for the currently selected pill — drives matchedGeometryEffect.
    private var selectionID: String {
        if isNowSelected { return "now" }
        if let tag = selectedCustomTag { return "tag-\(tag)" }
        if let cat = selectedCategory { return cat.rawValue }
        return "all"
    }

    /// Iterate `allCases` (not the `Set`) so pill order stays stable and
    /// matches enum declaration order.
    private var visibleCategories: [ExperienceCategory] {
        Self.visiblePills(from: preferences.visibleCategories)
    }

    /// Pure function exposed for unit testing — keeps pill ordering tied to
    /// `ExperienceCategory.allCases` and filters by the user's chosen set.
    static func visiblePills(from selection: Set<ExperienceCategory>) -> [ExperienceCategory] {
        ExperienceCategory.allCases.filter { selection.contains($0) }
    }

    public var body: some View {
        GlassmorphismCapsule(horizontalPadding: 0, verticalPadding: 0) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    nowPill(isSelected: isNowSelected, action: onSelectNow)
                    pill(
                        id: "all",
                        label: NSLocalizedString("filter.all", comment: "All"),
                        isSelected: !isNowSelected && selectedCategory == nil && selectedCustomTag == nil,
                        color: Color.primary,
                        action: onSelectAll
                    )
                    ForEach(visibleCategories) { category in
                        iconPill(
                            category: category,
                            isSelected: selectionID == category.rawValue,
                            action: { onSelectCategory(category) }
                        )
                    }
                    ForEach(preferences.customTags, id: \.self) { tag in
                        customTagPill(
                            tag: tag,
                            isSelected: selectionID == "tag-\(tag)",
                            action: { onSelectCustomTag(tag) }
                        )
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .animation(.spring(response: 0.4, dampingFraction: 0.75), value: selectionID)
            }
        }
        .padding(.horizontal, 16)
        .opacity(isMapPanning ? 0.4 : 1.0)
        .scaleEffect(isMapPanning ? 0.85 : 1.0)
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: isMapPanning)
        .onTapGesture { isMapPanning = false }
    }

    private static let accentGold = Color(red: 0xD4/255, green: 0xA8/255, blue: 0x43/255)

    private func nowPill(isSelected: Bool, action: @escaping () -> Void) -> some View {
        let label = NSLocalizedString("filter.now", comment: "Now")
        let a11yLabel: String = nowCount > 0
            ? String(format: NSLocalizedString("filter.now.a11y", comment: "Now, n experiences at their best"), nowCount)
            : label

        return Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            action()
        } label: {
            HStack(spacing: 5) {
                Circle()
                    .fill(isSelected ? Color.white : Self.accentGold)
                    .frame(width: 6, height: 6)
                    .scaleEffect(isPulsing ? 1.4 : 1.0)
                    .opacity(isPulsing ? 0.5 : 1.0)

                Text(label)
                    .font(.subheadline.weight(.medium))

                if nowCount > 0 {
                    Text("\(nowCount)")
                        .font(.caption2.monospacedDigit().weight(.semibold))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(
                            Capsule().fill(isSelected ? Color.white.opacity(0.3) : Self.accentGold.opacity(0.25))
                        )
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .foregroundStyle(isSelected ? .white : .primary)
            .background(
                Capsule().fill(isSelected ? Self.accentGold : Color.clear)
            )
            .overlay(
                Capsule().stroke(isSelected ? Color.clear : Color.primary.opacity(0.2), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(a11yLabel))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .onAppear {
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
    }

    private func pill(id: String, label: String, isSelected: Bool, color: Color, action: @escaping () -> Void) -> some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            action()
        } label: {
            Text(label)
                .font(.subheadline.weight(.medium))
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
                .overlay(alignment: .topTrailing) {
                    if isSelected && resultCount > 0 {
                        countBadge(count: resultCount, tint: color)
                            .offset(x: 6, y: -6)
                            .transition(.scale.combined(with: .opacity))
                    }
                }
                .animation(.spring(response: 0.3, dampingFraction: 0.65), value: resultCount)
        }
        .buttonStyle(PressableButtonStyle())
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityValue(isSelected && resultCount > 0 ? Text("\(resultCount) results") : Text(""))
    }

    private func iconPill(category: ExperienceCategory, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            action()
        } label: {
            Image(systemName: category.symbol)
                .font(.body.weight(.semibold))
                .frame(width: 36, height: 36)
                .foregroundStyle(isSelected ? .white : category.color)
                .background {
                    if isSelected {
                        Circle()
                            .fill(category.color)
                            .matchedGeometryEffect(id: "filterHighlight", in: pillHighlight)
                    }
                }
                .overlay(
                    Circle().stroke(isSelected ? Color.clear : category.color.opacity(0.4), lineWidth: 1)
                )
                .overlay(alignment: .topTrailing) {
                    if isSelected && resultCount > 0 {
                        countBadge(count: resultCount, tint: category.color)
                            .offset(x: 6, y: -6)
                            .transition(.scale.combined(with: .opacity))
                    }
                }
                .animation(.spring(response: 0.3, dampingFraction: 0.65), value: resultCount)
        }
        .buttonStyle(PressableButtonStyle())
        .accessibilityLabel(Text(category.localizedTitle))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityValue(isSelected && resultCount > 0 ? Text("\(resultCount) results") : Text(""))
    }

    /// Pill rendered for each entry in `UserPreferences.customTags`. Same
    /// shape as `iconPill` (36×36 circle, tag.fill glyph, accent color), so
    /// it visually reads as part of the same filter row. US-008.
    private func customTagPill(tag: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            action()
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
    }

    @ViewBuilder
    private func countBadge(count: Int, tint: Color) -> some View {
        Text("\(count)")
            .font(.caption2.weight(.semibold).monospacedDigit())
            .foregroundStyle(.white)
            .padding(.horizontal, 5)
            .frame(minWidth: 16, minHeight: 16)
            .background(Capsule().fill(tint))
    }
}

// MARK: - PressableButtonStyle

/// Scales down ~8% on press and springs back, giving pills a physical feel.
private struct PressableButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.92 : 1.0)
            .animation(.spring(response: 0.25, dampingFraction: 0.6), value: configuration.isPressed)
    }
}

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
