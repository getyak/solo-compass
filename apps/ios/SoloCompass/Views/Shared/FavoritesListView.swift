import SwiftUI

/// List of favorited experiences sorted by most-recently-added.
/// Presented as a sheet from SettingsView or via the map settings button.
public struct FavoritesListView: View {
    @Environment(ExperienceService.self) private var experienceService
    @Environment(UserPreferences.self) private var preferences
    let onSelectExperience: (Experience) -> Void

    @State private var lastUnfavorited: (id: String, date: Date)?
    @State private var undoDismissTask: Task<Void, Never>?

    private var sortedFavorites: [Experience] {
        let ids = preferences.favoritedExperiences
        let experiences = ids.compactMap { experienceService.getExperience(id: $0) }
        return experiences.sorted { lhs, rhs in
            let lDate = preferences.favoritedAt[lhs.id] ?? .distantPast
            let rDate = preferences.favoritedAt[rhs.id] ?? .distantPast
            return lDate > rDate
        }
    }

    public var body: some View {
        NavigationStack {
            Group {
                if sortedFavorites.isEmpty && lastUnfavorited == nil {
                    emptyState
                        .transition(.opacity)
                } else {
                    List(sortedFavorites) { exp in
                        favoriteRow(exp)
                    }
                    .listStyle(.plain)
                    .animation(.easeInOut, value: sortedFavorites.count)
                    .transition(.opacity)
                }
            }
            .animation(.easeInOut, value: sortedFavorites.isEmpty)
            .navigationTitle(NSLocalizedString("favorites.title", comment: "Favorites list title"))
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .overlay(alignment: .bottom) {
            if lastUnfavorited != nil {
                undoBar
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .padding(.bottom, 16)
            }
        }
        .animation(.easeInOut, value: lastUnfavorited != nil)
        .onDisappear {
            undoDismissTask?.cancel()
            undoDismissTask = nil
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "heart.slash")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text(NSLocalizedString("favorites.empty.title", comment: "No favorites yet"))
                .font(.headline)
            Text(NSLocalizedString("favorites.empty.hint", comment: "Tap the heart on any experience"))
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(32)
    }

    private var undoBar: some View {
        HStack {
            Text(NSLocalizedString("favorites.undo", comment: "Removed — Undo banner"))
                .font(.subheadline)
                .foregroundStyle(.primary)
            Spacer()
            Button {
                guard let saved = lastUnfavorited else { return }
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                undoDismissTask?.cancel()
                undoDismissTask = nil
                withAnimation(.easeInOut) {
                    preferences.toggleFavorite(saved.id, at: saved.date)
                    lastUnfavorited = nil
                }
            } label: {
                Text(NSLocalizedString("action.undo", comment: "Undo action"))
                    .font(.subheadline.weight(.semibold))
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    @ViewBuilder
    private func favoriteRow(_ exp: Experience) -> some View {
        Button {
            onSelectExperience(exp)
        } label: {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(exp.category.color.opacity(0.15))
                        .frame(width: 44, height: 44)
                    Image(systemName: exp.category.symbol)
                        .font(.body)
                        .foregroundStyle(exp.category.color)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(exp.title)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Text(exp.oneLiner)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button(role: .destructive) {
                let generator = UINotificationFeedbackGenerator()
                generator.prepare()
                generator.notificationOccurred(.warning)
                let savedDate = preferences.favoritedAt[exp.id] ?? Date()
                let expId = exp.id
                undoDismissTask?.cancel()
                withAnimation(.easeInOut) {
                    preferences.toggleFavorite(expId)
                    lastUnfavorited = (id: expId, date: savedDate)
                }
                undoDismissTask = Task {
                    do {
                        try await Task.sleep(for: .seconds(4))
                    } catch {
                        return
                    }
                    await MainActor.run {
                        withAnimation(.easeInOut) {
                            lastUnfavorited = nil
                        }
                    }
                }
            } label: {
                Label(NSLocalizedString("action.unfavorite", comment: "Remove from favorites"),
                      systemImage: "heart.slash")
            }
        }
    }
}

#Preview {
    FavoritesListView(onSelectExperience: { _ in })
        .environment(ExperienceService())
        .environment(UserPreferences())
}
