import SwiftUI

/// Full-screen list of routes the current user has walked.
///
/// Stub for US-030 — shows the same routes as the horizontal scroll
/// in CompanionProfileView but in a vertical list layout.
public struct MyWalkedRoutesListView: View {
    let routes: [Route]

    public init(routes: [Route]) {
        self.routes = routes
    }

    public var body: some View {
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
        .navigationTitle(
            String(
                format: NSLocalizedString("profile.walkedRoutes.header", comment: "Walked routes section header"),
                routes.count
            )
        )
        .navigationBarTitleDisplayMode(.large)
    }
}

#Preview {
    NavigationStack {
        MyWalkedRoutesListView(routes: [])
    }
}
