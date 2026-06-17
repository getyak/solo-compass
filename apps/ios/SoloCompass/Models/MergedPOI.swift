import Foundation
import CoreLocation

// MARK: - Source Provenance

/// Source provenance metadata attached to each enrichment signal.
/// Tracks which data source contributed what fields and its reliability weight.
public struct SourceEnrichment: Codable, Equatable {
    public enum SourceName: String, Codable {
        case osm = "osm"
        case amap = "amap"
        case foursquare = "foursquare"
        case mapkit = "mapkit"
        case wikivoyage = "wikivoyage"
        case googlePlaces = "google_places"
        case webSearch = "web_search"
        case userGenerated = "ugc"
    }

    public let source: SourceName
    /// Reliability weight (0.0-1.0). Higher = more trusted for conflict resolution.
    public let weight: Double
    /// Which fields this source contributed (e.g. "name", "hours", "rating").
    public let contributedFields: Set<String>
    public let fetchedAt: Date

    public init(source: SourceName, weight: Double, contributedFields: Set<String>, fetchedAt: Date = Date()) {
        self.source = source
        self.weight = min(max(weight, 0), 1)
        self.contributedFields = contributedFields
        self.fetchedAt = fetchedAt
    }
}

// MARK: - Field Conflict

/// When two sources disagree on the same field, record the conflict
/// so downstream synthesis can make an informed choice.
public struct FieldConflict: Codable, Equatable {
    public let field: String
    public let values: [SourcedValue]

    public struct SourcedValue: Codable, Equatable {
        public let source: SourceEnrichment.SourceName
        public let value: String
        public let weight: Double
    }

    /// The winning value -- highest weight source wins.
    public var resolvedValue: String? {
        values.max(by: { $0.weight < $1.weight })?.value
    }
}

// MARK: - MergedPOI

/// Typed intermediate between raw POI fetch and AI synthesis.
/// Carries the base POI plus all enrichment signals, conflict flags,
/// and a merge confidence score. Replaces the ad-hoc merge in EnrichmentAgent.
public struct MergedPOI: Equatable {
    public let base: BasePOI
    public let enrichments: [SourceEnrichment]
    public let conflicts: [FieldConflict]
    /// 0.0-1.0 based on source agreement. Higher when multiple sources corroborate.
    public let mergeConfidence: Double

    /// Minimal POI representation from the primary source.
    public struct BasePOI: Equatable {
        public let osmId: Int64
        public let name: String
        public let nameEn: String?
        public let coordinate: CLLocationCoordinate2D
        public let tags: [String: String]
        public let primarySource: SourceEnrichment.SourceName
    }

    public init(
        base: BasePOI,
        enrichments: [SourceEnrichment],
        conflicts: [FieldConflict] = [],
        mergeConfidence: Double
    ) {
        self.base = base
        self.enrichments = enrichments
        self.conflicts = conflicts
        self.mergeConfidence = min(max(mergeConfidence, 0), 1)
    }

    /// Number of distinct sources that contributed data.
    public var sourceCount: Int {
        Set(enrichments.map(\.source)).count
    }

    /// Whether this POI has conflicting information across sources.
    public var hasConflicts: Bool { !conflicts.isEmpty }

    /// Compute merge confidence from source agreement.
    /// Single source = 0.3, two agreeing = 0.6, three+ = 0.8+
    public static func computeConfidence(sourceCount: Int, conflictCount: Int) -> Double {
        let baseConfidence: Double
        switch sourceCount {
        case 0: baseConfidence = 0.0
        case 1: baseConfidence = 0.3
        case 2: baseConfidence = 0.6
        default: baseConfidence = 0.8
        }
        let conflictPenalty = Double(conflictCount) * 0.1
        return max(0, min(1, baseConfidence - conflictPenalty))
    }
}

// MARK: - Equatable for BasePOI

// CLLocationCoordinate2D doesn't conform to Equatable by default
extension MergedPOI.BasePOI {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.osmId == rhs.osmId
            && lhs.name == rhs.name
            && lhs.nameEn == rhs.nameEn
            && lhs.coordinate.latitude == rhs.coordinate.latitude
            && lhs.coordinate.longitude == rhs.coordinate.longitude
            && lhs.tags == rhs.tags
            && lhs.primarySource == rhs.primarySource
    }
}
