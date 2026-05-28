import Foundation
import os.log

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
}
