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

    /// Namespace for the shared gliding selection highlight.
    @Namespace private var pillHighlight

    /// User's chosen subset of categories. Injected via SwiftUI environment
    /// (US-006). Previews/tests that don't supply preferences get a freshly
    /// constructed `UserPreferences`, which defaults to all 8 categories.
    @Environment(UserPreferences.self) private var preferences

    public init(
        selectedCategory: ExperienceCategory?,
        isNowSelected: Bool,
        selectedCustomTag: String? = nil,
        onSelectNow: @escaping () -> Void,
        onSelectAll: @escaping () -> Void,
        onSelectCategory: @escaping (ExperienceCategory) -> Void,
        onSelectCustomTag: @escaping (String) -> Void = { _ in },
        isMapPanning: Binding<Bool> = .constant(false)
    ) {
        self.selectedCategory = selectedCategory
        self.isNowSelected = isNowSelected
        self.selectedCustomTag = selectedCustomTag
        self.onSelectNow = onSelectNow
        self.onSelectAll = onSelectAll
        self.onSelectCategory = onSelectCategory
        self.onSelectCustomTag = onSelectCustomTag
        self._isMapPanning = isMapPanning
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
                    pill(
                        label: NSLocalizedString("filter.now", comment: "Now"),
                        isSelected: isNowSelected,
                        color: Color(red: 0xD4/255, green: 0xA8/255, blue: 0x43/255),
                        action: onSelectNow
                    )
                    pill(
                        label: NSLocalizedString("filter.all", comment: "All"),
                        isSelected: !isNowSelected && selectedCategory == nil && selectedCustomTag == nil,
                        color: Color.primary,
                        action: onSelectAll
                    )
                    ForEach(visibleCategories) { category in
                        iconPill(
                            category: category,
                            isSelected: selectedCategory == category,
                            action: { onSelectCategory(category) }
                        )
                    }
                    ForEach(preferences.customTags, id: \.self) { tag in
                        customTagPill(
                            tag: tag,
                            isSelected: selectedCustomTag == tag,
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

    private func pill(label: String, isSelected: Bool, color: Color, action: @escaping () -> Void) -> some View {
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
        }
        .buttonStyle(PressableButtonStyle())
        .accessibilityAddTraits(isSelected ? .isSelected : [])
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
                        Capsule()
                            .fill(category.color)
                            .matchedGeometryEffect(id: "filterHighlight", in: pillHighlight)
                    }
                }
                .overlay(
                    Circle().stroke(isSelected ? Color.clear : category.color.opacity(0.4), lineWidth: 1)
                )
        }
        .buttonStyle(PressableButtonStyle())
        .accessibilityLabel(Text(category.localizedTitle))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
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
                        Capsule()
                            .fill(Color.accentColor)
                            .matchedGeometryEffect(id: "filterHighlight", in: pillHighlight)
                    }
                }
                .overlay(
                    Circle().stroke(isSelected ? Color.clear : Color.accentColor.opacity(0.4), lineWidth: 1)
                )
        }
        .buttonStyle(PressableButtonStyle())
        .accessibilityLabel(Text(tag))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
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
            onSelectNow: {},
            onSelectAll: {},
            onSelectCategory: { _ in }
        )
        FilterBarView(
            selectedCategory: nil,
            isNowSelected: true,
            onSelectNow: {},
            onSelectAll: {},
            onSelectCategory: { _ in }
        )
    }
    .padding(.vertical)
    .background(Color(red: 0xF5/255, green: 0xF0/255, blue: 0xE8/255))
    .environment(UserPreferences())
}
