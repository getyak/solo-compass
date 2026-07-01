import Foundation
import Observation
import os

/// P3.2 #321: composes a shareable "Solo Brag" card from a trip's
/// VisitRecord sequence + a manually-entered flourish counter.
///
/// Output is a plain data struct (`BragCardData`) that `BragCardView`
/// (#322) renders. The view can also request a video export
/// (`com.solocompass.consumable.brag.video`, #323) that ImageRenderer
/// converts frame-by-frame.
///
/// Design notes:
/// - **Copy is spare, not effusive.** One number > three adjectives.
/// - **Deterministic**: same visits + same flourish counters → same
///   "one-line story" so a user regenerating (free) doesn't feel gambled.
/// - **Privacy**: no coordinates leak into the card; only counts +
///   cityCode + a headline drawn from a static pool.
@MainActor
@Observable
public final class BragCardComposer {

    public static let shared = BragCardComposer()

    private let log = OSLog(subsystem: "com.solocompass.app", category: "Brag")

    public init() {}

    /// Optional flourish counters the user self-reports at the end of a
    /// trip (Cups of coffee, smiles-at-strangers, etc). All optional so
    /// the composer never blocks on user input.
    public struct Flourishes: Equatable, Codable, Sendable {
        public var coffeesConsumed: Int?
        public var smilesShared: Int?
        public var stepsWalked: Int?

        public init(
            coffeesConsumed: Int? = nil,
            smilesShared: Int? = nil,
            stepsWalked: Int? = nil
        ) {
            self.coffeesConsumed = coffeesConsumed
            self.smilesShared = smilesShared
            self.stepsWalked = stepsWalked
        }
    }

    /// Compose the card. `experiences` is the full Experience objects for
    /// the trip's VisitRecord rows — passed by the caller so we don't
    /// re-hit SwiftData here.
    public func compose(
        cityCode: String,
        visits: [VisitRecord],
        experiences: [Experience],
        flourishes: Flourishes = .init(),
        now: Date = Date(),
        calendar: Calendar = Calendar.current
    ) -> BragCardData {
        let distinctIds = Set(visits.map { $0.experienceId })
        let distinctExperienceCount = distinctIds.count

        let approxDistanceKm = Self.approxDistanceKm(visits: visits)

        let earliest = visits.map { $0.visitedAt }.min() ?? now
        let dayCount = max(1, (calendar.dateComponents([.day], from: earliest, to: now).day ?? 0) + 1)

        let headline = Self.headline(cityCode: cityCode, dayCount: dayCount)
        let anchor = Self.mostVisitedExperience(from: visits, in: experiences)

        return BragCardData(
            cityCode: cityCode,
            dayCount: dayCount,
            distinctExperienceCount: distinctExperienceCount,
            approxDistanceKm: approxDistanceKm,
            flourishes: flourishes,
            headline: headline,
            anchorExperienceTitle: anchor?.title,
            createdAt: now
        )
    }

    // MARK: - Helpers

    static func approxDistanceKm(visits: [VisitRecord]) -> Double {
        guard visits.count >= 2 else { return 0 }
        var total: Double = 0
        var last: (lon: Double, lat: Double)?
        for v in visits {
            guard let arr = v.coords, arr.count == 2 else { continue }
            let cur = (lon: arr[0], lat: arr[1])
            if let prev = last {
                total += haversineKm(from: prev, to: cur)
            }
            last = cur
        }
        return total
    }

    static func haversineKm(
        from a: (lon: Double, lat: Double),
        to b: (lon: Double, lat: Double)
    ) -> Double {
        let R = 6371.0
        let φ1 = a.lat * .pi / 180
        let φ2 = b.lat * .pi / 180
        let dφ = (b.lat - a.lat) * .pi / 180
        let dλ = (b.lon - a.lon) * .pi / 180
        let h = sin(dφ / 2) * sin(dφ / 2)
            + cos(φ1) * cos(φ2) * sin(dλ / 2) * sin(dλ / 2)
        let c = 2 * atan2(sqrt(h), sqrt(1 - h))
        return R * c
    }

    static func mostVisitedExperience(
        from visits: [VisitRecord],
        in pool: [Experience]
    ) -> Experience? {
        var counts: [String: Int] = [:]
        for v in visits {
            counts[v.experienceId, default: 0] += 1
        }
        let sorted = counts.sorted { $0.value > $1.value }
        guard let topId = sorted.first?.key else { return nil }
        return pool.first { $0.id == topId }
    }

    static func headline(cityCode: String, dayCount: Int) -> String {
        let cityUpper = cityCode.uppercased()
        let pool = [
            "\(cityUpper) — went slow, on purpose.",
            "\(dayCount) days in \(cityUpper). Nothing rushed.",
            "\(cityUpper) knew when to be quiet.",
            "Kept my own pace in \(cityUpper).",
        ]
        var hash: UInt64 = 0
        for byte in "\(cityCode)|\(dayCount)".utf8 {
            hash ^= UInt64(byte)
            hash &*= 1099511628211
        }
        return pool[Int(hash % UInt64(pool.count))]
    }
}

/// P3.2 #321 payload — rendered by BragCardView (#322).
public struct BragCardData: Codable, Hashable, Sendable {
    public let cityCode: String
    public let dayCount: Int
    public let distinctExperienceCount: Int
    public let approxDistanceKm: Double
    public let flourishes: BragCardComposer.Flourishes
    public let headline: String
    public let anchorExperienceTitle: String?
    public let createdAt: Date
}
