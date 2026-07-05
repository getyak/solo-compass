import Foundation
import CoreLocation
import SwiftUI

// swiftlint:disable:next orphaned_doc_comment
/// Experience — the core unit of Solo Compass.
///
/// NOT a place. NOT a POI. A concrete, time-bound, story-rich thing worth
/// doing, anchored to a place but not reducible to it.
///
/// Mirrors `packages/core/src/experience.ts`. Keep field names in sync.

// MARK: - Category

/// The kind of activity an experience represents, used to group and filter the map.
public enum ExperienceCategory: String, Codable, CaseIterable, Identifiable, Hashable {
    case culture, nature, food, coffee, work, wellness, nightlife, hidden

    public var id: String { rawValue }

    /// SF Symbol used on the filter bar.
    public var symbol: String {
        switch self {
        case .culture:   return "building.columns"
        case .nature:    return "leaf"
        case .food:      return "fork.knife"
        case .coffee:    return "cup.and.saucer"
        case .work:      return "laptopcomputer"
        case .wellness:  return "heart.circle"
        case .nightlife: return "moon.stars"
        case .hidden:    return "sparkles"
        }
    }

    /// Brand color per category — uses UIKit semantic colors that adapt to dark/light mode.
    public var color: Color {
        switch self {
        case .culture:   return Color(.systemOrange).opacity(0.85)
        case .nature:    return Color(.systemGreen)
        case .food:      return Color(.systemRed)
        case .coffee:    return Color(.systemBrown)
        case .work:      return Color(.systemBlue)
        case .wellness:  return Color(.systemTeal)
        case .nightlife: return Color(.systemPurple)
        case .hidden:    return Color(.systemGray)
        }
    }

    public var localizedTitle: String {
        NSLocalizedString("category.\(rawValue)", comment: "Experience category")
    }
}

// MARK: - Time window

/// A recurring slot when an experience is at its best, scoped by hour, weekday, and season.
public struct TimeWindow: Codable, Hashable {
    public let startHour: Int       // 0–23
    public let endHour: Int         // 0–23
    public let dayOfWeek: [Int]?    // 0=Sun..6=Sat
    public let season: [Int]?       // months 1-12
    public let note: String?

    public init(startHour: Int, endHour: Int, dayOfWeek: [Int]? = nil, season: [Int]? = nil, note: String? = nil) {
        self.startHour = startHour
        self.endHour = endHour
        self.dayOfWeek = dayOfWeek
        self.season = season
        self.note = note
    }

    /// Is the window open at the given hour (local)?
    public func contains(hour: Int) -> Bool {
        if startHour <= endHour { return hour >= startHour && hour < endHour }
        // wraps midnight
        return hour >= startHour || hour < endHour
    }
}

// MARK: - Location

/// Where an experience happens: its coordinates plus enriched place details like
/// rating, hours, and contact info pulled from map providers.
public struct ExperienceLocation: Codable, Hashable {
    /// GeoJSON convention: [longitude, latitude].
    public let coordinates: [Double]
    public let cityCode: String
    public let addressHint: String?
    public let placeNameLocal: String?
    public let placeNameRomanized: String?
    // Cross-channel hard signals enriched from Foursquare / Apple MapKit.
    // All optional; OSM-only places leave them nil. Mirrors the TS schema.
    public let rating: Double?         // 0–10 normalized provider rating
    public let openingHours: String?   // raw provider hours string
    public let priceLevel: Double?     // 1–4 (1 = cheap, 4 = expensive)
    public let website: String?
    public let phone: String?
    /// Photos attached to the place. User-created experiences populate this from
    /// the photo picker; seed/OSM places leave it nil. Values are URL strings:
    /// local `file://` paths until synced, then remote https URLs. Mirrors TS.
    public let photoUrls: [String]?

    public var clCoordinate: CLLocationCoordinate2D? {
        guard coordinates.count >= 2 else { return nil }
        return CLLocationCoordinate2D(latitude: coordinates[1], longitude: coordinates[0])
    }

    /// Returns a copy with `photoUrls` replaced. Used when photos resolve after
    /// the location was first built (e.g. async Wikidata enrichment).
    public func withPhotoUrls(_ urls: [String]?) -> ExperienceLocation {
        ExperienceLocation(
            coordinates: coordinates, cityCode: cityCode, addressHint: addressHint,
            placeNameLocal: placeNameLocal, placeNameRomanized: placeNameRomanized,
            rating: rating, openingHours: openingHours, priceLevel: priceLevel,
            website: website, phone: phone, photoUrls: urls
        )
    }

    public init(
        coordinates: [Double],
        cityCode: String,
        addressHint: String? = nil,
        placeNameLocal: String? = nil,
        placeNameRomanized: String? = nil,
        rating: Double? = nil,
        openingHours: String? = nil,
        priceLevel: Double? = nil,
        website: String? = nil,
        phone: String? = nil,
        photoUrls: [String]? = nil
    ) {
        self.coordinates = coordinates
        self.cityCode = cityCode
        self.addressHint = addressHint
        self.placeNameLocal = placeNameLocal
        self.placeNameRomanized = placeNameRomanized
        self.rating = rating
        self.openingHours = openingHours
        self.priceLevel = priceLevel
        self.website = website
        self.phone = phone
        self.photoUrls = photoUrls
    }
}

// MARK: - HowTo step

/// A single ordered instruction in the step-by-step guide for doing an experience.
public struct HowToStep: Codable, Hashable, Identifiable {
    public let order: Int
    public let text: String
    public var id: Int { order }

    public init(order: Int, text: String) {
        self.order = order
        self.text = text
    }
}

// MARK: - Real inconvenience

/// An honest heads-up about a downside of an experience — scams, crowds, weather, etc.
public struct RealInconvenience: Codable, Hashable, Identifiable {
    /// How seriously a warning should be presented to the traveler.
    public enum Severity {
        case high, medium, low

        public var backgroundOpacity: Double {
            switch self {
            case .high:   return 0.10
            case .medium: return 0.08
            case .low:    return 0.06
            }
        }
    }

    /// The kind of inconvenience a traveler might encounter at an experience.
    public enum Category: String, Codable, Hashable {
        case scam, crowds, logistics, weather, etiquette, safety, other

        public var symbol: String {
            switch self {
            case .scam:      return "exclamationmark.shield"
            case .crowds:    return "person.3.fill"
            case .logistics: return "map"
            case .weather:   return "cloud.rain"
            case .etiquette: return "hand.raised"
            case .safety:    return "shield.lefthalf.filled"
            case .other:     return "info.circle"
            }
        }

        public var severity: Severity {
            switch self {
            case .scam, .safety:                       return .high
            case .crowds, .weather, .logistics, .etiquette: return .medium
            case .other:                               return .low
            }
        }

        public var label: String {
            switch self {
            case .safety:    return NSLocalizedString("inconvenience.category.safety", comment: "Inconvenience category: safety")
            case .scam:      return NSLocalizedString("inconvenience.category.scam", comment: "Inconvenience category: scam")
            case .crowds:    return NSLocalizedString("inconvenience.category.crowds", comment: "Inconvenience category: crowds")
            case .logistics: return NSLocalizedString("inconvenience.category.logistics", comment: "Inconvenience category: logistics")
            case .weather:   return NSLocalizedString("inconvenience.category.weather", comment: "Inconvenience category: weather")
            case .etiquette: return NSLocalizedString("inconvenience.category.etiquette", comment: "Inconvenience category: etiquette")
            case .other:     return NSLocalizedString("inconvenience.category.other", comment: "Inconvenience category: note/other")
            }
        }
    }

    public let category: Category
    public let text: String
    public var id: String { "\(category.rawValue)-\(text.hashValue)" }

    public init(category: Category, text: String) {
        self.category = category
        self.text = text
    }
}

// MARK: - Solo Score

/// How comfortable an experience is for someone visiting alone, as an overall
/// rating plus the factors that produced it.
public struct SoloScore: Codable, Hashable {
    /// The individual solo-friendliness factors that combine into the overall score.
    public struct Breakdown: Codable, Hashable {
        public let seatingFriendly: Double
        public let soloPatronRatio: Double
        public let staffPressure: Double
        public let soloPortioning: Double
        public let ambianceFit: Double
        public let safety: Double

        public init(
            seatingFriendly: Double,
            soloPatronRatio: Double,
            staffPressure: Double,
            soloPortioning: Double,
            ambianceFit: Double,
            safety: Double
        ) {
            self.seatingFriendly = seatingFriendly
            self.soloPatronRatio = soloPatronRatio
            self.staffPressure = staffPressure
            self.soloPortioning = soloPortioning
            self.ambianceFit = ambianceFit
            self.safety = safety
        }
    }

    public let overall: Double      // 0-10
    public let breakdown: Breakdown
    public let hint: String?
    public let basedOnCount: Int

    public init(overall: Double, breakdown: Breakdown, hint: String? = nil, basedOnCount: Int) {
        self.overall = overall
        self.breakdown = breakdown
        self.hint = hint
        self.basedOnCount = basedOnCount
    }

    /// Visual color for the overall score: red→yellow→green.
    public var scoreColor: Color {
        let clamped = max(0, min(10, overall))
        let normalized = clamped / 10.0
        if normalized < 0.5 {
            // red → yellow
            return Color(red: 1.0, green: normalized * 2, blue: 0.2)
        } else {
            // yellow → green
            return Color(red: 1.0 - (normalized - 0.5) * 2, green: 0.85, blue: 0.2)
        }
    }
}

// MARK: - Category highlight

/// A category-specific, scannable fact surfaced on the card — the detail that
/// matters most for *this kind* of place. A café highlight might be
/// "Wi-Fi · fast", a meal "Signature · pho bo", a temple "Best light · sunrise".
///
/// Kept deliberately generic (icon + label + value) so the LLM can emit a
/// different *set* of highlights per category without the schema growing a
/// dozen optional columns, and the UI renders them all with one pill view.
/// Only facts derivable from real signals/tags should be filled — never invented.
public struct CategoryHighlight: Codable, Hashable, Identifiable {
    /// A small, fixed vocabulary of highlight kinds. The raw value doubles as a
    /// stable id and selects the SF Symbol + accent, so the LLM picks from this
    /// set rather than free-forming icons.
    public enum Kind: String, Codable, Hashable, CaseIterable {
        // food
        case signature        // a dish/specialty the place is known for
        case pricePerPerson   // typical spend for one
        case waitTime         // expect a queue / walk right in
        // coffee / work
        case wifi             // wifi availability / quality
        case power            // power outlets at seats
        case longStay         // comfortable to linger 2h+
        // culture / nature
        case bestLight        // golden hour / best time to see
        case ticket           // entry fee / free
        case duration         // how long to budget
        // wellness / nightlife / generic
        case booking          // reservation needed / walk-in
        case vibe             // ambiance one-word
        case note             // anything else worth a glance

        /// SF Symbol shown on the highlight pill.
        public var symbol: String {
            switch self {
            case .signature:      return "star.circle"
            case .pricePerPerson: return "yensign.circle"
            case .waitTime:       return "hourglass"
            case .wifi:           return "wifi"
            case .power:          return "powerplug"
            case .longStay:       return "clock.arrow.circlepath"
            case .bestLight:      return "sun.max"
            case .ticket:         return "ticket"
            case .duration:       return "timer"
            case .booking:        return "calendar"
            case .vibe:           return "sparkles"
            case .note:           return "info.circle"
            }
        }
    }

    public let kind: Kind
    /// Short noun for the fact, e.g. "Wi-Fi", "Signature". Localized upstream
    /// (model emits it in the requested output language).
    public let label: String
    /// The actual value, e.g. "fast", "pho bo", "free". Kept under ~4 words.
    public let value: String

    public var id: String { "\(kind.rawValue)-\(value)" }

    public init(kind: Kind, label: String, value: String) {
        self.kind = kind
        self.label = label
        self.value = value
    }
}

// MARK: - Health & Confidence

/// How likely an experience is still real and accurate, shown to travelers as a
/// freshness indicator from healthy to possibly gone.
public enum HealthStatus: String, Codable {
    case healthy
    case fading
    case questioned
    case mayBeGone

    public var symbol: String {
        switch self {
        case .healthy:    return "checkmark.circle.fill"
        case .fading:     return "clock.badge.questionmark"
        case .questioned: return "exclamationmark.circle.fill"
        case .mayBeGone:  return "xmark.circle.fill"
        }
    }

    public var color: Color {
        switch self {
        case .healthy:    return .green
        case .fading:     return .yellow
        case .questioned: return .red
        case .mayBeGone:  return .secondary // adaptive — visible in both light and dark mode
        }
    }

    public var localizedDescription: String {
        NSLocalizedString("health.\(rawValue)", comment: "Health status label")
    }

    /// SF Symbol to overlay on the compact dot so colorblind users can distinguish states by shape.
    public var accessibilitySymbol: String? {
        switch self {
        case .healthy:    return nil
        case .fading:     return "clock"
        case .questioned: return "questionmark"
        case .mayBeGone:  return "xmark"
        }
    }
}

/// How much we trust that an experience's information is current, derived from
/// when it was last verified and the signals backing it up.
public struct Confidence: Codable, Hashable {
    /// The raw evidence behind a confidence level: scrape age, GPS visits, and reports.
    public struct Signals: Codable, Hashable {
        public let aiScrapeAgeDays: Int
        public let passiveGpsHits30d: Int
        public let activeReports30d: Int
        public let trustedVerifications: Int

        public init(aiScrapeAgeDays: Int, passiveGpsHits30d: Int, activeReports30d: Int, trustedVerifications: Int) {
            self.aiScrapeAgeDays = aiScrapeAgeDays
            self.passiveGpsHits30d = passiveGpsHits30d
            self.activeReports30d = activeReports30d
            self.trustedVerifications = trustedVerifications
        }

        public var totalCount: Int {
            passiveGpsHits30d + activeReports30d + trustedVerifications
        }
    }

    public let level: Int           // 0–5
    public let lastVerifiedAt: Date
    public let reason: String
    public let signals: Signals

    public init(level: Int, lastVerifiedAt: Date, reason: String, signals: Signals) {
        self.level = max(0, min(5, level))
        self.lastVerifiedAt = lastVerifiedAt
        self.reason = reason
        self.signals = signals
    }

    /// Mirror of `healthFromConfidence` in TS.
    public var health: HealthStatus {
        let ageDays = Date().timeIntervalSince(lastVerifiedAt) / 86_400
        if ageDays > 60 { return .mayBeGone }
        if level >= 3 && ageDays < 30 { return .healthy }
        if level >= 2 && ageDays < 30 { return .fading }
        return .questioned
    }
}

// MARK: - Information Source

/// An attributed origin for an experience's information — where the details came
/// from and when that source was last verified.
public struct InformationSource: Codable, Hashable, Identifiable {
    /// The kind of place an experience's information was sourced from.
    public enum SourceType: String, Codable, Hashable {
        // `amap` marks AutoNavi/高德 as provenance for mainland-China POIs.
        // Per ADR-amap-china-poi §3.2 only this attribution flag persists,
        // never the raw structured fields (address/phone/rating/hours).
        case wikivoyage, wikipedia, reddit, blog, youtube, user, fieldVisit = "field_visit", amap
    }

    public let type: SourceType
    public let url: URL?
    public let attribution: String?
    public let verifiedAt: Date

    public var id: String {
        "\(type.rawValue)-\(url?.absoluteString ?? attribution ?? UUID().uuidString)"
    }

    public init(type: SourceType, url: URL? = nil, attribution: String? = nil, verifiedAt: Date) {
        self.type = type
        self.url = url
        self.attribution = attribution
        self.verifiedAt = verifiedAt
    }
}

// MARK: - Experience

/// The core unit of Solo Compass: a concrete, time-bound, story-rich thing worth
/// doing alone, bundling its location, timing, guidance, score, and provenance.
public struct Experience: Codable, Hashable, Identifiable {
    /// The typical shortest-to-longest time, in minutes, an experience takes.
    public struct DurationRange: Codable, Hashable {
        public let min: Int
        public let max: Int
        public init(min: Int, max: Int) { self.min = min; self.max = max }
    }

    /// Aggregate usage data for an experience: how often it's been done and how it rated.
    public struct Stats: Codable, Hashable {
        public let completionCount: Int
        public let averageRating: Double // 0-5
        public let lastCompletedAt: Date?
        public init(completionCount: Int, averageRating: Double, lastCompletedAt: Date? = nil) {
            self.completionCount = completionCount
            self.averageRating = averageRating
            self.lastCompletedAt = lastCompletedAt
        }
    }

    /// Where an experience sits in its lifecycle, from unverified candidate to retired.
    public enum Status: String, Codable, Hashable {
        case candidate, active, stale, retired
    }

    public let id: String
    public let title: String
    public let oneLiner: String
    public let whyItMatters: String
    public let category: ExperienceCategory
    public let location: ExperienceLocation
    public let bestTimes: [TimeWindow]
    public let durationMinutes: DurationRange
    public let howTo: [HowToStep]
    /// Category-specific scannable facts (Wi-Fi for cafés, signature dish for
    /// food, best light for sights). Optional + decoded leniently so older
    /// persisted/seed entries without it stay valid; treated as `[]` in the UI.
    public let categoryHighlights: [CategoryHighlight]?
    public let realInconveniences: [RealInconvenience]
    public let soloScore: SoloScore
    public let sources: [InformationSource]
    public let confidence: Confidence
    public let nearbyExperienceIds: [String]
    public let stats: Stats
    public let status: Status
    public let createdAt: Date
    public let updatedAt: Date

    /// User-defined free-form tags layered on top of the category enum.
    /// Optional in JSON; treated as `[]` everywhere a non-nil array is expected.
    public let userTags: [String]?

    public init(
        id: String,
        title: String,
        oneLiner: String,
        whyItMatters: String,
        category: ExperienceCategory,
        location: ExperienceLocation,
        bestTimes: [TimeWindow],
        durationMinutes: DurationRange,
        howTo: [HowToStep],
        realInconveniences: [RealInconvenience],
        soloScore: SoloScore,
        sources: [InformationSource],
        confidence: Confidence,
        nearbyExperienceIds: [String],
        stats: Stats,
        status: Status,
        createdAt: Date,
        updatedAt: Date,
        userTags: [String]? = nil,
        categoryHighlights: [CategoryHighlight]? = nil
    ) {
        self.id = id
        self.title = title
        self.oneLiner = oneLiner
        self.whyItMatters = whyItMatters
        self.category = category
        self.location = location
        self.bestTimes = bestTimes
        self.durationMinutes = durationMinutes
        self.howTo = howTo
        self.realInconveniences = realInconveniences
        self.soloScore = soloScore
        self.sources = sources
        self.confidence = confidence
        self.nearbyExperienceIds = nearbyExperienceIds
        self.stats = stats
        self.status = status
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.userTags = userTags
        self.categoryHighlights = categoryHighlights
    }

    public var coordinate: CLLocationCoordinate2D? { location.clCoordinate }

    /// Non-nil category highlights, never nil — UI iterates this directly.
    public var highlights: [CategoryHighlight] { categoryHighlights ?? [] }

    /// Compact display name: romanized place name → local name → full title.
    public var shortName: String {
        let candidates = [location.placeNameRomanized, location.placeNameLocal]
        if let name = candidates.compactMap({ $0 }).first(where: { !$0.isEmpty }) {
            return name
        }
        return title
    }

    /// True when this entry was discovered via OpenStreetMap Explore
    /// (vs. a curated seed entry). Used to surface provenance in the UI.
    public var isFromOpenStreetMap: Bool { id.hasPrefix("exp_osm_") }

    /// ID prefix for experiences a user creates by hand. Mirrors
    /// `EXP_USER_ID_PREFIX` in packages/core/src/experience.ts.
    public static let userIdPrefix = "exp_user_"

    /// True when the user registered this place themselves. Drives a distinct
    /// "unverified / user-created" marker and badge in the UI.
    public var isUserCreated: Bool { id.hasPrefix(Self.userIdPrefix) }

    /// Build a candidate `Experience` from raw user input. Trust-critical fields
    /// are forced to safe, unverified defaults — the user never scores their own
    /// place. Mirrors `createUserExperience` in packages/core/src/experience.ts.
    ///
    /// - Parameters:
    ///   - uuid: caller-supplied unique id (e.g. `UUID().uuidString`).
    ///   - now: creation timestamp; defaults to current date.
    public static func userDraft(
        uuid: String,
        title: String,
        oneLiner: String,
        category: ExperienceCategory,
        coordinates: [Double],
        cityCode: String,
        placeNameRomanized: String? = nil,
        placeNameLocal: String? = nil,
        addressHint: String? = nil,
        description: String = "",
        photoUrls: [String]? = nil,
        userTags: [String]? = nil,
        now: Date = Date()
    ) -> Experience {
        Experience(
            id: "\(userIdPrefix)\(uuid)",
            title: title,
            oneLiner: oneLiner,
            whyItMatters: description,
            category: category,
            location: ExperienceLocation(
                coordinates: coordinates,
                cityCode: cityCode,
                addressHint: addressHint,
                placeNameLocal: placeNameLocal,
                placeNameRomanized: placeNameRomanized,
                photoUrls: photoUrls
            ),
            bestTimes: [],
            durationMinutes: DurationRange(min: 30, max: 60),
            howTo: [],
            realInconveniences: [],
            soloScore: SoloScore(
                overall: 5,
                breakdown: SoloScore.Breakdown(
                    seatingFriendly: 5,
                    soloPatronRatio: 5,
                    staffPressure: 5,
                    soloPortioning: 5,
                    ambianceFit: 5,
                    safety: 5
                ),
                basedOnCount: 0
            ),
            sources: [InformationSource(type: .user, verifiedAt: now)],
            confidence: Confidence(
                level: 1,
                lastVerifiedAt: now,
                reason: "User-created, awaiting verification",
                signals: Confidence.Signals(
                    aiScrapeAgeDays: 0,
                    passiveGpsHits30d: 0,
                    activeReports30d: 0,
                    trustedVerifications: 0
                )
            ),
            nearbyExperienceIds: [],
            stats: Stats(completionCount: 0, averageRating: 0),
            status: .candidate,
            createdAt: now,
            updatedAt: now,
            userTags: userTags
        )
    }

    /// True only when the entry actually went through AI synthesis. The
    /// `skeletonExperience` fallback (network/quota failure, missing key)
    /// produces an OSM entry with no AI enrichment — its sources omit the
    /// "+ AI" attribution. Distinguishing the two prevents the detail view
    /// from labelling a raw, template-filled skeleton as "AI-generated".
    public var isAIEnriched: Bool {
        sources.contains { ($0.attribution ?? "").localizedCaseInsensitiveContains("AI") }
    }

    /// True for hand-curated seed entries: not user-created, not discovered via
    /// OSM/Amap, and without multi-source verification. Mirrors the `.curated`
    /// fallback in `trustBadgeLevel`. These cards carry human-written copy and
    /// scores, so the silent auto-upgrade path must never overwrite them.
    public var isCuratedSeed: Bool {
        guard !isUserCreated, !isFromOpenStreetMap else { return false }
        let distinctTypes = Set(sources.map(\.type))
        return distinctTypes.count < 2 && !distinctTypes.contains(.amap)
    }

    /// Returns a new Experience with selected fields overridden. Use this when
    /// mutating tracked stats/status/location/etc. without rewriting all 18 init
    /// args. `location` lets callers swap in an enriched location (e.g. photos
    /// resolved after synthesis) without rebuilding the whole value.
    public func copy(
        location: ExperienceLocation? = nil,
        stats: Stats? = nil,
        status: Status? = nil,
        updatedAt: Date? = nil
    ) -> Experience {
        Experience(
            id: id, title: title, oneLiner: oneLiner, whyItMatters: whyItMatters,
            category: category, location: location ?? self.location, bestTimes: bestTimes,
            durationMinutes: durationMinutes, howTo: howTo, realInconveniences: realInconveniences,
            soloScore: soloScore, sources: sources, confidence: confidence,
            nearbyExperienceIds: nearbyExperienceIds,
            stats: stats ?? self.stats,
            status: status ?? self.status,
            createdAt: createdAt,
            updatedAt: updatedAt ?? self.updatedAt,
            userTags: self.userTags,
            categoryHighlights: self.categoryHighlights
        )
    }

    /// The representative "ideal start hour" for this experience: the earliest
    /// `startHour` across all `bestTimes` windows, or `nil` when there are none.
    /// Used as the Gaussian center for `HourOfDaySignal`.
    public var bestStartHour: Int? {
        bestTimes.map(\.startHour).min()
    }

    /// A continuous timeliness score in `[0, 1]` for the given date.
    ///
    /// Iterates the registered signals and produces a *weight-normalized*
    /// average of their values, concatenating each signal's reason with ` · `.
    /// "Weight-normalized" matters: each signal exposes a `weight` (bestTimes
    /// 0.4, hourOfDay 0.2 today), but `composeNowScore` divides by the **sum**
    /// of participating weights — so the absolute weight is meaningless and
    /// only the relative ratio (bestTimes counts twice as much as hourOfDay)
    /// shapes the verdict. Adding or removing a signal doesn't require
    /// rebalancing the others. An empty signal list yields `0.5`.
    public func nowScore(at date: Date = Date()) -> NowScore {
        // Delegates to the shared engine. The synchronous path runs the two pure,
        // local signals; the failure-tolerant async path (`NowScoreEngine.evaluate`)
        // is used once network-backed signals (weather, sunset) join the registry.
        NowScoreEngine.evaluateSync(for: self, at: date)
    }

    /// Weight-normalized composition of signal contributions, shared by
    /// `nowScore(at:)` and `NowSignalCompositionTests`.
    /// Empty input → neutral `0.5`.
    static func composeNowScore(
        from signals: [(key: String, contribution: NowSignalContribution)]
    ) -> NowScore {
        guard !signals.isEmpty else {
            return NowScore(value: 0.5, reason: nil, breakdown: [:])
        }
        let totalWeight = signals.reduce(0.0) { $0 + $1.contribution.weight }
        let value = totalWeight > 0
            ? signals.reduce(0.0) { $0 + $1.contribution.value * $1.contribution.weight } / totalWeight
            : 0.5
        var breakdown: [String: Double] = [:]
        for signal in signals {
            breakdown[signal.key] = signal.contribution.value
        }
        // US-007: order reasons by contribution strength (weight × value) so the
        // most decisive signal leads the human-readable reason. The original
        // index is a stable tiebreaker for equal strengths, preserving input
        // order (and the existing composition-test assertions).
        var ranked: [(rank: Double, order: Int, text: String)] = []
        for (idx, signal) in signals.enumerated() {
            guard let reason = signal.contribution.reason else { continue }
            let strength = signal.contribution.weight * signal.contribution.value
            ranked.append((rank: strength, order: idx, text: reason))
        }
        ranked.sort { lhs, rhs in
            lhs.rank != rhs.rank ? lhs.rank > rhs.rank : lhs.order < rhs.order
        }
        let reasons = ranked.map(\.text)
        return NowScore(
            value: value,
            reason: reasons.isEmpty ? nil : reasons.joined(separator: " · "),
            breakdown: breakdown
        )
    }

    /// US-007: condenses a `NowScore.reason` into a one-line badge subtitle.
    ///
    /// The reason already arrives sorted by contribution strength (weight ×
    /// value) from `composeNowScore`; here we keep the top-3 ` · `-separated
    /// segments and ellipsize when the rejoined text exceeds `maxChars`.
    /// Returns `nil` when the score has no reason, letting the caller fall back
    /// to a localized "此刻" label.
    static func nowReasonSubtitle(for score: NowScore, maxChars: Int = 28) -> String? {
        guard let reason = score.reason, !reason.isEmpty else { return nil }
        let segments = reason.components(separatedBy: " · ").prefix(3)
        let combined = segments.joined(separator: " · ")
        guard combined.count > maxChars else { return combined }
        return String(combined.prefix(maxChars - 1)) + "…"
    }

    /// Returns a copy of `source`'s richer content (title, copy, signals,
    /// sources, confidence) re-keyed onto THIS experience's identity. Used by
    /// the deep-dive re-compile flow: the place stays the same entry (same id,
    /// same favorite/completion state, same createdAt), but its information is
    /// upgraded with cross-source enriched data. The user's tracked state
    /// (stats, userTags, status) is preserved from `self`, not overwritten.
    public func adoptingContent(of source: Experience) -> Experience {
        Experience(
            id: id,
            title: source.title,
            oneLiner: source.oneLiner,
            whyItMatters: source.whyItMatters,
            category: source.category,
            location: source.location,
            bestTimes: source.bestTimes,
            durationMinutes: source.durationMinutes,
            howTo: source.howTo,
            realInconveniences: source.realInconveniences,
            soloScore: source.soloScore,
            sources: source.sources,
            confidence: source.confidence,
            nearbyExperienceIds: source.nearbyExperienceIds,
            stats: self.stats,
            status: self.status,
            createdAt: self.createdAt,
            updatedAt: Date(),
            userTags: self.userTags
        )
    }

    /// Is any of this experience's `bestTimes` open right now?
    public func isBestNow(at date: Date = Date()) -> Bool {
        return nowScore(at: date).value >= 0.7
    }

    /// Minutes remaining in the currently-active bestTimes window, or nil when not best now.
    /// Handles windows that wrap past midnight (endHour < startHour).
    ///
    /// **Time-zone contract (#72):** `bestTimes.startHour/endHour` are
    /// interpreted in the **device's current local time** via
    /// `Calendar.current`. The Experience model deliberately does NOT carry a
    /// `placeTimezone` field today — solo travelers overwhelmingly browse
    /// places near their current location (the map centers on the user) and
    /// the device tz tracks them. When the design eventually supports
    /// browse-from-afar (e.g. saved Hanoi places while sitting in New York),
    /// add `Experience.placeTimezone: String?` and switch this Calendar to a
    /// place-tz-anchored one — the rest of the logic (window matching,
    /// midnight wrap) carries over unchanged. Until then, accept the known
    /// edge case rather than silently mis-rendering "best now" for far-away
    /// places.
    public func minutesLeftInBestWindow(at date: Date = Date()) -> Int? {
        let cal = Calendar.current
        let hour = cal.component(.hour, from: date)
        let weekday = cal.component(.weekday, from: date) - 1 // Sun=0
        let month = cal.component(.month, from: date)

        let activeWindow = bestTimes.first { window in
            if let days = window.dayOfWeek, !days.isEmpty, !days.contains(weekday) { return false }
            if let seasons = window.season, !seasons.isEmpty, !seasons.contains(month) { return false }
            return window.contains(hour: hour)
        }

        guard let window = activeWindow else { return nil }

        // Build the next wall-clock occurrence of endHour from `date`.
        var components = cal.dateComponents([.year, .month, .day], from: date)
        components.hour = window.endHour
        components.minute = 0
        components.second = 0
        guard var end = cal.date(from: components) else { return nil }

        // If endHour <= startHour the window crosses midnight; advance by one day
        // so that `end` is always in the future relative to `date`.
        if window.endHour <= window.startHour || end <= date {
            end = cal.date(byAdding: .day, value: 1, to: end) ?? end
        }

        let minutes = Int(end.timeIntervalSince(date) / 60)
        // Return 0 when the window has effectively closed (< 1 minute left),
        // not the previous min-clamp of 1. UI surfaces should special-case 0
        // to read "即将关闭 / Closing now" instead of misreporting "1m left"
        // when the window is actually closing within seconds (see #73).
        return max(0, minutes)
    }
}

// MARK: - Best Time Hint

extension Experience {
    /// Returns a localized short time range (e.g. "7–9am", "6pm") for the soonest
    /// applicable bestTimes window when the experience is NOT currently at its best.
    /// Returns nil when isBestNow() is true or when bestTimes is empty.
    public func bestTimeHint(at date: Date = Date()) -> String? {
        guard !isBestNow(at: date) else { return nil }
        guard !bestTimes.isEmpty else { return nil }

        let cal = Calendar.current
        let weekday = cal.component(.weekday, from: date) - 1 // Sun=0
        let month = cal.component(.month, from: date)
        let currentHour = cal.component(.hour, from: date)

        let applicable = bestTimes.filter { window in
            if let days = window.dayOfWeek, !days.isEmpty, !days.contains(weekday) { return false }
            if let seasons = window.season, !seasons.isEmpty, !seasons.contains(month) { return false }
            return true
        }

        let pool = applicable.isEmpty ? bestTimes : applicable

        // Prefer windows whose start is still ahead today; fall back to earliest overall.
        let upcoming = pool.filter { $0.startHour > currentHour }
        let chosen = upcoming.min(by: { $0.startHour < $1.startHour }) ?? pool.min(by: { $0.startHour < $1.startHour })

        guard let window = chosen else { return nil }
        return Self.formatTimeRange(startHour: window.startHour, endHour: window.endHour)
    }

    /// True when `bestTimeHint(at:)` would surface a window whose soonest
    /// occurrence is *tomorrow* rather than later today — i.e. every applicable
    /// window has already started by `date`, so the hint wraps to the earliest
    /// window overall (which next opens the following morning).
    ///
    /// A bare "Best 7–9am" reads the same at 8am (opens later today) and at 11pm
    /// (already passed; really means tomorrow). Callers use this to append a
    /// "tomorrow" qualifier so the two cases don't look identical. Returns false
    /// when there is no hint to qualify (best now, no best times, or a window
    /// still opening later today).
    public func nextBestWindowIsTomorrow(at date: Date = Date()) -> Bool {
        guard !isBestNow(at: date) else { return false }
        guard !bestTimes.isEmpty else { return false }

        let cal = Calendar.current
        let weekday = cal.component(.weekday, from: date) - 1 // Sun=0
        let month = cal.component(.month, from: date)
        let currentHour = cal.component(.hour, from: date)

        let applicable = bestTimes.filter { window in
            if let days = window.dayOfWeek, !days.isEmpty, !days.contains(weekday) { return false }
            if let seasons = window.season, !seasons.isEmpty, !seasons.contains(month) { return false }
            return true
        }
        let pool = applicable.isEmpty ? bestTimes : applicable

        // Mirror bestTimeHint's selection: if any window starts later today the
        // hint refers to today; only when none do does it fall back to the
        // earliest window overall, which next opens tomorrow.
        guard !pool.isEmpty else { return false }
        return !pool.contains { $0.startHour > currentHour }
    }

    private static func formatTimeRange(startHour: Int, endHour: Int) -> String {
        let cal = Calendar.current
        var start = cal.startOfDay(for: Date())
        start = cal.date(byAdding: .hour, value: startHour, to: start) ?? start
        var end = cal.startOfDay(for: Date())
        end = cal.date(byAdding: .hour, value: endHour, to: end) ?? end

        let fmt = DateFormatter()
        fmt.locale = Locale.current
        fmt.dateFormat = Locale.current.uses24HourClock ? "H" : "ha"
        fmt.amSymbol = "am"
        fmt.pmSymbol = "pm"

        let startStr = fmt.string(from: start)
        let endStr = fmt.string(from: end)

        // Collapse suffix when both share the same am/pm period (12h only)
        if !Locale.current.uses24HourClock {
            let startPeriod = startHour < 12 ? "am" : "pm"
            let endPeriod = endHour < 12 ? "am" : "pm"
            if startPeriod == endPeriod {
                // e.g. "7–9am"
                let shortFmt = DateFormatter()
                shortFmt.locale = Locale.current
                shortFmt.dateFormat = "h"
                let shortStart = shortFmt.string(from: start)
                return "\(shortStart)–\(endStr)"
            }
        }
        return "\(startStr)–\(endStr)"
    }

    /// Minutes until the soonest applicable `bestTimes` window *opens* later today,
    /// or nil when the experience is already best now, has no upcoming window today,
    /// or the soonest window is further out than `within` minutes.
    ///
    /// Powers an "opens soon" nudge on the best-time hint pill: a static
    /// "Best 7–9am" reads the same whether the window opens in 20 minutes or in
    /// 8 hours, so callers use this to highlight only the imminent case.
    public func minutesUntilNextBestWindow(at date: Date = Date(), within: Int = 90) -> Int? {
        guard !isBestNow(at: date) else { return nil }
        guard !bestTimes.isEmpty else { return nil }

        let cal = Calendar.current
        let weekday = cal.component(.weekday, from: date) - 1 // Sun=0
        let month = cal.component(.month, from: date)
        let currentHour = cal.component(.hour, from: date)

        let applicable = bestTimes.filter { window in
            if let days = window.dayOfWeek, !days.isEmpty, !days.contains(weekday) { return false }
            if let seasons = window.season, !seasons.isEmpty, !seasons.contains(month) { return false }
            return true
        }
        let pool = applicable.isEmpty ? bestTimes : applicable

        // Only windows that start later today (same logic as bestTimeHint's
        // `upcoming`); a window already underway is handled by isBestNow above.
        guard let nextStartHour = pool
            .map(\.startHour)
            .filter({ $0 > currentHour })
            .min()
        else { return nil }

        var components = cal.dateComponents([.year, .month, .day], from: date)
        components.hour = nextStartHour
        components.minute = 0
        components.second = 0
        guard let opensAt = cal.date(from: components) else { return nil }

        let minutes = Int((opensAt.timeIntervalSince(date) / 60).rounded(.up))
        guard minutes > 0, minutes <= within else { return nil }
        return minutes
    }
}

private extension Locale {
    var uses24HourClock: Bool {
        let fmt = DateFormatter()
        fmt.locale = self
        fmt.dateStyle = .none
        fmt.timeStyle = .short
        let sample = fmt.string(from: Date())
        return !sample.contains(fmt.amSymbol) && !sample.contains(fmt.pmSymbol)
    }
}

// MARK: - Marker State

/// The visual state of an experience's pin on the map, reflecting timing and the
/// traveler's own relationship to it (favorited, completed, upcoming, visited).
public enum ExperienceMarkerState: Hashable {
    case `default`
    case bestNow
    case completed
    case favorited
    case upcoming(minutes: Int)
    case footprinted

    /// Stable string fragment used in accessibility identifiers.
    public var identifierFragment: String {
        switch self {
        case .default:    return "default"
        case .bestNow:    return "bestNow"
        case .completed:  return "completed"
        case .favorited:  return "favorited"
        case .upcoming:   return "upcoming"
        case .footprinted: return "footprinted"
        }
    }
}
