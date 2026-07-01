import Foundation
import Observation
import SwiftData

/// View model for the Travel Archive tab (P1.1 #111).
///
/// Joins `VisitRecord` (where the user has been) against `ExperienceRecord`
/// (the canonical Experience metadata) to build a city-grouped timeline.
///
/// Pure read model — never writes. Refresh is explicit so the view controls
/// when SwiftData fetches happen (e.g. on appear, after returning from a
/// detail sheet).
@MainActor
@Observable
public final class ArchiveViewModel {

    /// One row in the timeline — a single visit decorated with the
    /// matching Experience's display fields.
    public struct VisitedExperience: Identifiable, Hashable {
        public let id: PersistentIdentifier
        public let experienceId: String
        public let title: String
        public let cityCode: String
        public let visitedAt: Date
        public let dwellSeconds: Int
    }

    /// All visits for a single city, newest first.
    public struct CityGroup: Identifiable, Hashable {
        public var id: String { cityCode }
        public let cityCode: String
        public let visits: [VisitedExperience]
        public var distinctExperienceCount: Int {
            Set(visits.map(\.experienceId)).count
        }
    }

    /// Trip summary card data shown above the timeline.
    public struct TripSummary: Hashable {
        public let cityCode: String
        public let firstVisitAt: Date
        public let lastVisitAt: Date
        public let distinctExperienceCount: Int

        /// Inclusive day span — same-day trip = 1, next-day = 2.
        public var dayCount: Int {
            let cal = Calendar.current
            let start = cal.startOfDay(for: firstVisitAt)
            let end = cal.startOfDay(for: lastVisitAt)
            let days = cal.dateComponents([.day], from: start, to: end).day ?? 0
            return max(1, days + 1)
        }
    }

    public private(set) var groups: [CityGroup] = []
    public private(set) var currentTrip: TripSummary?
    public private(set) var totalVisitCount: Int = 0
    public private(set) var isEmpty: Bool = true

    private let modelContainer: ModelContainer

    /// City code used to pick the "current trip" group. When nil, the most
    /// recent visit's city wins. Callers pass a city when the user is actively
    /// in one (so the trip card stays anchored even after a stale visit log).
    public var activeCityCode: String?

    public init(modelContainer: ModelContainer, activeCityCode: String? = nil) {
        self.modelContainer = modelContainer
        self.activeCityCode = activeCityCode
    }

    // MARK: - Refresh

    /// Re-fetch all visits and rebuild the grouped view model. Cheap enough
    /// to call from `onAppear` — SwiftData backs this with an indexed query.
    public func refresh() {
        let context = ModelContext(modelContainer)

        let visits: [VisitRecord]
        do {
            var descriptor = FetchDescriptor<VisitRecord>(
                sortBy: [SortDescriptor(\.visitedAt, order: .reverse)]
            )
            descriptor.fetchLimit = 500 // archive view is browsing-grade; bound the query
            visits = try context.fetch(descriptor)
        } catch {
            visits = []
        }

        totalVisitCount = visits.count

        // Resolve each visit's Experience metadata in a single bulk fetch
        // keyed by id, instead of N round-trips.
        let ids = Array(Set(visits.map(\.experienceId)))
        let experienceById: [String: ExperienceRecord]
        if ids.isEmpty {
            experienceById = [:]
        } else {
            do {
                let predicate = #Predicate<ExperienceRecord> { ids.contains($0.id) }
                let records = try context.fetch(FetchDescriptor<ExperienceRecord>(predicate: predicate))
                experienceById = Dictionary(uniqueKeysWithValues: records.map { ($0.id, $0) })
            } catch {
                experienceById = [:]
            }
        }

        // Decorate each visit, dropping orphans (Experience deleted from cache).
        let rows: [VisitedExperience] = visits.compactMap { v in
            guard let exp = experienceById[v.experienceId] else { return nil }
            return VisitedExperience(
                id: v.persistentModelID,
                experienceId: v.experienceId,
                title: exp.title,
                cityCode: exp.cityCode,
                visitedAt: v.visitedAt,
                dwellSeconds: v.dwellSeconds
            )
        }

        // Group by city, preserving the global newest-first sort within each group.
        var byCity: [String: [VisitedExperience]] = [:]
        var cityOrder: [String] = []
        for row in rows {
            if byCity[row.cityCode] == nil {
                byCity[row.cityCode] = []
                cityOrder.append(row.cityCode)
            }
            byCity[row.cityCode]?.append(row)
        }
        groups = cityOrder.map { CityGroup(cityCode: $0, visits: byCity[$0] ?? []) }

        currentTrip = buildCurrentTrip(rows: rows)
        isEmpty = rows.isEmpty
    }

    // MARK: - Trip summary

    private func buildCurrentTrip(rows: [VisitedExperience]) -> TripSummary? {
        guard !rows.isEmpty else { return nil }

        // Prefer the explicitly-set active city; fall back to the most recent.
        let targetCity = activeCityCode ?? rows.first?.cityCode
        guard let city = targetCity else { return nil }

        let cityRows = rows.filter { $0.cityCode == city }
        guard !cityRows.isEmpty else { return nil }

        // rows are sorted newest-first, so first = last visit, last = first visit
        let lastVisit = cityRows.first!.visitedAt
        let firstVisit = cityRows.last!.visitedAt
        let distinct = Set(cityRows.map(\.experienceId)).count
        return TripSummary(
            cityCode: city,
            firstVisitAt: firstVisit,
            lastVisitAt: lastVisit,
            distinctExperienceCount: distinct
        )
    }
}
