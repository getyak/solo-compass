/// Bidirectional converters between Itinerary and Route.
///
/// Story #US-005. Route is becoming the canonical core; Itinerary is the
/// existing user-facing surface. These pure converters let both coexist so
/// the itinerary UI keeps working while downstream features migrate to Route.
///
/// Itinerary-only fields (ownerId, dates, openToCompanions, timestamps,
/// note-vs-nil) are carried on the Route via a `tags` prefix convention so a
/// round-trip `Itinerary -> Route -> Itinerary` is lossless.

// MARK: - Tag conventions

private enum ItineraryBridge {
    static let prefix = "itinerary:"

    static let startDateKey = "startDate"
    static let endDateKey = "endDate"
    static let openToCompanionsKey = "openToCompanions"
    static let createdAtKey = "createdAt"
    static let updatedAtKey = "updatedAt"
    static let hasNoteKey = "hasNote"

    static func tag(_ key: String, _ value: String) -> String {
        "\(prefix)\(key)=\(value)"
    }

    static func value(forKey key: String, in tags: [String]) -> String? {
        let needle = "\(prefix)\(key)="
        guard let match = tags.first(where: { $0.hasPrefix(needle) }) else {
            return nil
        }
        return String(match.dropFirst(needle.count))
    }
}

// MARK: - Itinerary -> Route

public extension Route {
    /// Build a Route from an Itinerary.
    ///
    /// The resulting Route has `source = .userCreated`, `companion = nil`,
    /// and `verification = RouteVerification(status: .proposed,
    /// walkedByCount: 0, walkedBy: [])`.
    init(itinerary: Itinerary) {
        let hasNote = itinerary.note != nil
        let tags: [String] = [
            ItineraryBridge.tag(ItineraryBridge.startDateKey, itinerary.startDate),
            ItineraryBridge.tag(ItineraryBridge.endDateKey, itinerary.endDate),
            ItineraryBridge.tag(ItineraryBridge.openToCompanionsKey, itinerary.openToCompanions ? "true" : "false"),
            ItineraryBridge.tag(ItineraryBridge.createdAtKey, itinerary.createdAt),
            ItineraryBridge.tag(ItineraryBridge.updatedAtKey, itinerary.updatedAt),
            ItineraryBridge.tag(ItineraryBridge.hasNoteKey, hasNote ? "true" : "false"),
        ]

        self.init(
            id: RouteId(rawValue: itinerary.id.rawValue),
            title: itinerary.title,
            summary: itinerary.note ?? "",
            experienceIds: itinerary.experienceIds,
            cityCode: itinerary.cityCode,
            region: "",
            estimatedDuration: 0,
            distanceMeters: 0,
            pace: .standard,
            tags: tags,
            source: .userCreated,
            authorId: itinerary.ownerId,
            bestStartHour: nil,
            bestNow: false,
            verification: RouteVerification(status: .proposed, walkedByCount: 0, walkedBy: []),
            companion: nil
        )
    }
}

// MARK: - Route -> Itinerary

public extension Itinerary {
    /// Build an Itinerary from a Route. Returns nil when
    /// `route.source != .userCreated`.
    init?(route: Route) {
        guard route.source == .userCreated else { return nil }
        guard let ownerId = route.authorId else { return nil }
        guard let startDate = ItineraryBridge.value(forKey: ItineraryBridge.startDateKey, in: route.tags) else { return nil }
        guard let endDate = ItineraryBridge.value(forKey: ItineraryBridge.endDateKey, in: route.tags) else { return nil }
        guard let createdAt = ItineraryBridge.value(forKey: ItineraryBridge.createdAtKey, in: route.tags) else { return nil }
        guard let updatedAt = ItineraryBridge.value(forKey: ItineraryBridge.updatedAtKey, in: route.tags) else { return nil }

        let openToCompanions = ItineraryBridge.value(forKey: ItineraryBridge.openToCompanionsKey, in: route.tags) == "true"
        let hasNote = ItineraryBridge.value(forKey: ItineraryBridge.hasNoteKey, in: route.tags) == "true"
        let note: String? = hasNote ? route.summary : nil

        self.init(
            id: ItineraryId(rawValue: route.id.rawValue),
            ownerId: ownerId,
            title: route.title,
            cityCode: route.cityCode,
            startDate: startDate,
            endDate: endDate,
            experienceIds: route.experienceIds,
            note: note,
            openToCompanions: openToCompanions,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }
}
