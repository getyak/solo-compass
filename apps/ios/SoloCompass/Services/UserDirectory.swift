import Foundation
import os.log
import SwiftUI

/// In-memory directory of seed users loaded from `seed_users.json`.
///
/// Populated once at app startup via `loadIfNeeded(bundle:)`. Provides
/// O(1) lookup by handle. No persistence — this is fixture data for P1 UI
/// states; real user profiles come from Supabase in later stories.
@MainActor
public final class UserDirectory {
    public static let shared = UserDirectory()

    private var usersByHandle: [String: SeedUser] = [:]
    private static let log = OSLog(subsystem: "com.solocompass.app", category: "UserDirectory")

    private init() {}

    /// Load `seed_users.json` from the given bundle into the in-memory
    /// dictionary. Idempotent: re-loading replaces the existing dictionary.
    public func loadIfNeeded(bundle: Bundle = .main) {
        guard let url = bundle.url(forResource: "seed_users", withExtension: "json") else {
            os_log(
                "UserDirectory: seed_users.json not found in bundle",
                log: Self.log,
                type: .error
            )
            return
        }
        do {
            let data = try Data(contentsOf: url)
            let users = try JSONDecoder().decode([SeedUser].self, from: data)
            usersByHandle = Dictionary(uniqueKeysWithValues: users.map { ($0.handle, $0) })
        } catch {
            os_log(
                "UserDirectory: failed to load seed_users.json: %{public}@",
                log: Self.log,
                type: .error,
                String(describing: error)
            )
        }
    }

    /// Look up a seed user by handle. Returns nil if not loaded or not found.
    public func user(handle: String) -> SeedUser? {
        usersByHandle[handle]
    }

    /// All loaded users, order unspecified.
    public var all: [SeedUser] {
        Array(usersByHandle.values)
    }

    /// Number of loaded users.
    public var count: Int {
        usersByHandle.count
    }

    // MARK: - Avatar color

    /// Deterministic avatar color for any string id.
    ///
    /// Returns the user's stored hex color when `id` matches a known handle;
    /// otherwise hashes `id` into a fixed palette so the color is stable
    /// across sessions without requiring a network lookup.
    @MainActor
    public static func color(forId id: String) -> Color {
        if let hex = shared.user(handle: id)?.color {
            return Color(hex: hex) ?? palette(id)
        }
        return palette(id)
    }

    private static let paletteHex: [String] = [
        "#E8826A", "#6AAEE8", "#82E8A0", "#E8D06A", "#C06AE8",
        "#E86AA0", "#6AE8D8", "#A0E86A", "#E8A06A", "#6A82E8",
    ]

    private static func palette(_ id: String) -> Color {
        let hash = id.unicodeScalars.reduce(0) { $0 &+ Int($1.value) }
        let hex = paletteHex[abs(hash) % paletteHex.count]
        return Color(hex: hex) ?? .gray
    }
}
