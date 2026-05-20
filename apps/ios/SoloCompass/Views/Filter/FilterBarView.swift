import SwiftUI

/// Top-of-screen pill bar. One tap, clear feedback. The whole bar slides in
/// over the map; we keep it visually light so the map stays the protagonist.
public struct FilterBarView: View {
    let selectedCategory: ExperienceCategory?
    let isNowSelected: Bool
    let onSelectNow: () -> Void
    let onSelectAll: () -> Void
    let onSelectCategory: (ExperienceCategory) -> Void

    public init(
        selectedCategory: ExperienceCategory?,
        isNowSelected: Bool,
        onSelectNow: @escaping () -> Void,
        onSelectAll: @escaping () -> Void,
        onSelectCategory: @escaping (ExperienceCategory) -> Void
    ) {
        self.selectedCategory = selectedCategory
        self.isNowSelected = isNowSelected
        self.onSelectNow = onSelectNow
        self.onSelectAll = onSelectAll
        self.onSelectCategory = onSelectCategory
    }

    private static let visibleCategories: [ExperienceCategory] = [
        .culture, .coffee, .food, .nature, .work, .wellness,
    ]

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
                        isSelected: !isNowSelected && selectedCategory == nil,
                        color: Color.primary,
                        action: onSelectAll
                    )
                    ForEach(Self.visibleCategories) { category in
                        iconPill(
                            category: category,
                            isSelected: selectedCategory == category,
                            action: { onSelectCategory(category) }
                        )
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
            }
        }
        .padding(.horizontal, 16)
        .animation(.easeInOut(duration: 0.2), value: selectedCategory)
        .animation(.easeInOut(duration: 0.2), value: isNowSelected)
    }

    private func pill(label: String, isSelected: Bool, color: Color, action: @escaping () -> Void) -> some View {
        Button {
            UISelectionFeedbackGenerator().selectionChanged()
            action()
        } label: {
            Text(label)
                .font(.subheadline.weight(.medium))
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .foregroundStyle(isSelected ? .white : .primary)
                .background(
                    Capsule().fill(isSelected ? color : Color.clear)
                )
                .overlay(
                    Capsule().stroke(isSelected ? Color.clear : Color.primary.opacity(0.2), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func iconPill(category: ExperienceCategory, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button {
            UISelectionFeedbackGenerator().selectionChanged()
            action()
        } label: {
            Image(systemName: category.symbol)
                .font(.body.weight(.semibold))
                .frame(width: 36, height: 36)
                .foregroundStyle(isSelected ? .white : category.color)
                .background(
                    Circle().fill(isSelected ? category.color : Color.clear)
                )
                .overlay(
                    Circle().stroke(isSelected ? Color.clear : category.color.opacity(0.4), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(category.localizedTitle))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
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
}
