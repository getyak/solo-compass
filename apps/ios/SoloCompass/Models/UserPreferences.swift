import Foundation
import Observation

/// User preferences persisted to UserDefaults.
///
/// Designed as a single Codable blob — small, atomic writes; easy to migrate.
/// We store under a single key (`UserPreferences.storageKey`) and re-encode on
/// every mutation. With <100 entries this stays well under the 4MB practical
/// limit on UserDefaults.
@Observable
public final class UserPreferences {
    public enum SoloTravelStyle: String, Codable, CaseIterable, Identifiable {
        case explorer, worker, foodie, cultureSeeker
        public var id: String { rawValue }
    }

    /// Snapshot used for Codable persistence. Mirrors the @Observable surface.
    private struct Snapshot: Codable {
        var preferredCategories: [ExperienceCategory] = []
        var dislikedCategories: [ExperienceCategory] = []
        var soloTravelStyle: SoloTravelStyle = .explorer
        var maxDistanceKm: Double = 5.0
        var visitHistory: [String: Date] = [:]
        var completedExperiences: Set<String> = []
        var favoritedExperiences: Set<String> = []
    }

    public var preferredCategories: [ExperienceCategory] { didSet { persist() } }
    public var dislikedCategories: [ExperienceCategory] { didSet { persist() } }
    public var soloTravelStyle: SoloTravelStyle { didSet { persist() } }
    public var maxDistanceKm: Double { didSet { persist() } }
    public var visitHistory: [String: Date] { didSet { persist() } }
    public var completedExperiences: Set<String> { didSet { persist() } }
    public var favoritedExperiences: Set<String> { didSet { persist() } }

    private static let storageKey = "com.solocompass.userPreferences.v1"
    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let snapshot = Self.load(from: defaults)
        self.preferredCategories = snapshot.preferredCategories
        self.dislikedCategories = snapshot.dislikedCategories
        self.soloTravelStyle = snapshot.soloTravelStyle
        self.maxDistanceKm = snapshot.maxDistanceKm
        self.visitHistory = snapshot.visitHistory
        self.completedExperiences = snapshot.completedExperiences
        self.favoritedExperiences = snapshot.favoritedExperiences
    }

    private static func load(from defaults: UserDefaults) -> Snapshot {
        guard
            let data = defaults.data(forKey: storageKey),
            let snapshot = try? JSONDecoder.iso8601Decoder.decode(Snapshot.self, from: data)
        else { return Snapshot() }
        return snapshot
    }

    private func persist() {
        let snapshot = Snapshot(
            preferredCategories: preferredCategories,
            dislikedCategories: dislikedCategories,
            soloTravelStyle: soloTravelStyle,
            maxDistanceKm: maxDistanceKm,
            visitHistory: visitHistory,
            completedExperiences: completedExperiences,
            favoritedExperiences: favoritedExperiences
        )
        guard let data = try? JSONEncoder.iso8601Encoder.encode(snapshot) else { return }
        defaults.set(data, forKey: Self.storageKey)
    }

    // MARK: - Convenience mutations

    public func markCompleted(_ id: String, at date: Date = Date()) {
        completedExperiences.insert(id)
        visitHistory[id] = date
    }

    public func toggleFavorite(_ id: String) {
        if favoritedExperiences.contains(id) {
            favoritedExperiences.remove(id)
        } else {
            favoritedExperiences.insert(id)
        }
    }

    public func isFavorited(_ id: String) -> Bool { favoritedExperiences.contains(id) }
    public func isCompleted(_ id: String) -> Bool { completedExperiences.contains(id) }
}

// MARK: - JSON helpers (shared, ISO8601 dates)

extension JSONDecoder {
    static let iso8601Decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()
}

extension JSONEncoder {
    static let iso8601Encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        return e
    }()
}
