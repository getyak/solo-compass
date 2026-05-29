import SwiftUI

/// Full-screen list of routes the current user has walked.
///
/// Stub for US-030 — shows the same routes as the horizontal scroll
/// in CompanionProfileView but in a vertical list layout.
public struct MyWalkedRoutesListView: View {
    let routes: [Route]
    var onExplore: (() -> Void)? = nil

    public init(routes: [Route], onExplore: (() -> Void)? = nil) {
        self.routes = routes
        self.onExplore = onExplore
    }

    public var body: some View {
        Group {
            if routes.isEmpty {
                WalkedRoutesEmptyState(onExplore: onExplore)
            } else {
                List(routes) { route in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(route.title)
                            .font(.headline)
                        Text(route.summary)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .navigationTitle(
            String(
                format: NSLocalizedString("profile.walkedRoutes.header", comment: "Walked routes section header"),
                routes.count
            )
        )
        .navigationBarTitleDisplayMode(.large)
    }
}

private struct WalkedRoutesEmptyState: View {
    var onExplore: (() -> Void)? = nil

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isBreathing = false

    var body: some View {
        VStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(Color.teal.opacity(0.12))
                    .frame(width: 80, height: 80)
                Image(systemName: "figure.walk")
                    .font(.system(size: 48))
                    .foregroundStyle(Color.teal.opacity(0.7))
                    .scaleEffect(isBreathing ? 1.08 : 0.94)
                    .opacity(isBreathing ? 1.0 : 0.7)
                    .animation(.easeInOut(duration: 1.6).repeatForever(autoreverses: true), value: isBreathing)
            }
            Text(NSLocalizedString("profile.walkedRoutes.empty.title", comment: "No walked routes yet"))
                .font(.headline)
            Text(NSLocalizedString("profile.walkedRoutes.empty.hint", comment: "Hint to explore routes"))
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            if let onExplore {
                Button {
                    Haptics.selection()
                    onExplore()
                } label: {
                    Label(NSLocalizedString("profile.walkedRoutes.empty.cta", comment: "Discover routes button in empty walked routes state"), systemImage: "map")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.regular)
                .padding(.top, 4)
            }
        }
        .padding(32)
        .onAppear {
            guard !isBreathing, !reduceMotion else { return }
            isBreathing = true
        }
    }
}

#Preview("MyWalkedRoutesListView — empty") {
    NavigationStack {
        MyWalkedRoutesListView(routes: [])
    }
}

#Preview("MyWalkedRoutesListView — with routes") {
    NavigationStack {
        MyWalkedRoutesListView(routes: [
            Route(
                id: RouteId(rawValue: "mekong-sunset"),
                title: "Mekong Sunset Walk",
                summary: "Dawn at the river, dusk by the ferry.",
                experienceIds: ["e1", "e2"],
                cityCode: "VTE",
                region: "Riverfront",
                estimatedDuration: 90,
                distanceMeters: 1200,
                pace: .relaxed,
                tags: ["nature"],
                source: .editorial
            ),
            Route(
                id: RouteId(rawValue: "old-quarter-coffee"),
                title: "Old Quarter Coffee Circuit",
                summary: "Four independent cafés in the heart of Hanoi.",
                experienceIds: ["e3", "e4"],
                cityCode: "HAN",
                region: "Old Quarter",
                estimatedDuration: 120,
                distanceMeters: 2200,
                pace: .standard,
                tags: ["coffee"],
                source: .editorial
            ),
        ])
    }
}
