import Foundation
import CoreLocation
import SwiftUI

/// Experience — the core unit of Solo Compass.
///
/// NOT a place. NOT a POI. A concrete, time-bound, story-rich thing worth
/// doing, anchored to a place but not reducible to it.
///
/// Mirrors `packages/core/src/experience.ts`. Keep field names in sync.

// MARK: - Category

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

    /// Brand color per category (hex from CLAUDE.md palette).
    public var color: Color {
        switch self {
        case .culture:   return Color(red: 0xE8/255, green: 0x77/255, blue: 0x22/255)
        case .nature:    return Color(red: 0x2D/255, green: 0x8C/255, blue: 0x4A/255)
        case .food:      return Color(red: 0xC4/255, green: 0x1E/255, blue: 0x3A/255)
        case .coffee:    return Color(red: 0x6F/255, green: 0x4E/255, blue: 0x37/255)
        case .work:      return Color(red: 0x25/255, green: 0x63/255, blue: 0xEB/255)
        case .wellness:  return Color(red: 0x7C/255, green: 0x3A/255, blue: 0xED/255)
        case .nightlife: return Color(red: 0x4F/255, green: 0x46/255, blue: 0xE5/255)
        case .hidden:    return Color(red: 0x6B/255, green: 0x72/255, blue: 0x80/255)
        }
    }

    public var localizedTitle: String {
        NSLocalizedString("category.\(rawValue)", comment: "Experience category")
    }
}

// MARK: - Time window

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

public struct ExperienceLocation: Codable, Hashable {
    /// GeoJSON convention: [longitude, latitude].
    public let coordinates: [Double]
    public let cityCode: String
    public let addressHint: String?
    public let placeNameLocal: String?
    public let placeNameRomanized: String?

    public var clCoordinate: CLLocationCoordinate2D {
        guard coordinates.count >= 2 else {
            return CLLocationCoordinate2D(latitude: 0, longitude: 0)
        }
        return CLLocationCoordinate2D(latitude: coordinates[1], longitude: coordinates[0])
    }

    public init(
        coordinates: [Double],
        cityCode: String,
        addressHint: String? = nil,
        placeNameLocal: String? = nil,
        placeNameRomanized: String? = nil
    ) {
        self.coordinates = coordinates
        self.cityCode = cityCode
        self.addressHint = addressHint
        self.placeNameLocal = placeNameLocal
        self.placeNameRomanized = placeNameRomanized
    }
}

// MARK: - HowTo step

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

public struct RealInconvenience: Codable, Hashable, Identifiable {
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

public struct SoloScore: Codable, Hashable {
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
        let t = clamped / 10.0
        if t < 0.5 {
            // red → yellow
            return Color(red: 1.0, green: t * 2, blue: 0.2)
        } else {
            // yellow → green
            return Color(red: 1.0 - (t - 0.5) * 2, green: 0.85, blue: 0.2)
        }
    }
}

// MARK: - Health & Confidence

public enum HealthStatus: String, Codable {
    case healthy
    case fading
    case questioned
    case mayBeGone

    public var symbol: String {
        switch self {
        case .healthy:   return "circle.fill"
        case .fading:    return "circle.fill"
        case .questioned: return "circle.fill"
        case .mayBeGone: return "circle.fill"
        }
    }

    public var color: Color {
        switch self {
        case .healthy:   return .green
        case .fading:    return .yellow
        case .questioned: return .red
        case .mayBeGone: return .black
        }
    }

    public var localizedDescription: String {
        NSLocalizedString("health.\(rawValue)", comment: "Health status label")
    }
}

public struct Confidence: Codable, Hashable {
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

public struct InformationSource: Codable, Hashable, Identifiable {
    public enum SourceType: String, Codable, Hashable {
        case wikivoyage, wikipedia, reddit, blog, youtube, user, fieldVisit = "field_visit"
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

public struct Experience: Codable, Hashable, Identifiable {
    public struct DurationRange: Codable, Hashable {
        public let min: Int
        public let max: Int
        public init(min: Int, max: Int) { self.min = min; self.max = max }
    }

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
    public let realInconveniences: [RealInconvenience]
    public let soloScore: SoloScore
    public let sources: [InformationSource]
    public let confidence: Confidence
    public let nearbyExperienceIds: [String]
    public let stats: Stats
    public let status: Status
    public let createdAt: Date
    public let updatedAt: Date

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
        updatedAt: Date
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
    }

    public var coordinate: CLLocationCoordinate2D { location.clCoordinate }

    /// Is any of this experience's `bestTimes` open right now?
    public func isBestNow(at date: Date = Date()) -> Bool {
        let hour = Calendar.current.component(.hour, from: date)
        let weekday = Calendar.current.component(.weekday, from: date) - 1 // Sun=0
        let month = Calendar.current.component(.month, from: date)
        return bestTimes.contains { window in
            if let days = window.dayOfWeek, !days.isEmpty, !days.contains(weekday) { return false }
            if let seasons = window.season, !seasons.isEmpty, !seasons.contains(month) { return false }
            return window.contains(hour: hour)
        }
    }
}

// MARK: - Marker State

public enum ExperienceMarkerState: Hashable {
    case `default`
    case bestNow
    case completed
    case favorited
    case upcoming(minutes: Int)
    case footprinted
}
