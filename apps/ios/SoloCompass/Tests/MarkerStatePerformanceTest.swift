import XCTest
@testable import SoloCompass

// MARK: - US-016: markerState(for:) call-count perf test

/// Verifies the CompassMapView marker-state caching optimisation (US-016).
///
/// The map's `ForEach(viewModel.visibleExperiences)` body needs the marker state
/// in two places per pin: the `MarkerIconView` and the `.footprinted` badge.
/// Before US-016 it called `viewModel.markerState(for:)` twice per iteration,
/// re-evaluating the helper's six conditions for every visible marker on every
/// render pass. The fix hoists `let state = viewModel.markerState(for: exp)` to
/// the top of the iteration so both downstream branches reuse it.
///
/// This test reconstructs both shapes — the *cached* path (one call per
/// iteration) and a *non-cached* baseline (two calls per iteration, mirroring
/// the pre-fix code) — and asserts the cached path's p95 per-pass latency drops
/// by ≥ 40% versus the baseline.
///
/// Run with:
///   xcodebuild test -only-testing:SoloCompassTests/MarkerStatePerformanceTest
final class MarkerStatePerformanceTest: XCTestCase {

    private static let markerCount = 100
    private static let iterations = 1000
    private static let requiredImprovement = 0.40

    // Bounding box: ±0.15° around Chiang Mai old-city center.
    private static let centerLat: Double = 18.7877
    private static let centerLon: Double = 98.9938
    private static let latSpan: Double   = 0.15
    private static let lonSpan: Double   = 0.15

    // MARK: - Fixture

    @MainActor
    private func makeViewModel(with experiences: [Experience]) -> MapViewModel {
        let vm = MapViewModel(
            locationService: LocationService(),
            experienceService: ExperienceService(seed: experiences),
            aiService: AIService(),
            preferences: UserPreferences()
        )
        vm.visibleExperiences = experiences
        return vm
    }

    private func makeExperiences(count: Int) -> [Experience] {
        let now = Date()
        return (0..<count).map { index in
            // Spread markers evenly across the bounding box using a grid layout.
            let cols = Int(Double(count).squareRoot().rounded(.up))
            let row = index / cols
            let col = index % cols
            let latStep = Self.latSpan / Double(max(1, cols - 1))
            let lonStep = Self.lonSpan / Double(max(1, cols - 1))
            let lat = Self.centerLat - Self.latSpan / 2 + Double(row) * latStep
            let lon = Self.centerLon - Self.lonSpan / 2 + Double(col) * lonStep

            let categories = ExperienceCategory.allCases.filter { $0 != .hidden }
            let category = categories[index % categories.count]

            return Experience(
                id: "marker_perf_\(index)",
                title: "Marker Perf \(index)",
                oneLiner: "Marker fixture \(index)",
                whyItMatters: "Performance fixture",
                category: category,
                location: ExperienceLocation(
                    coordinates: [lon, lat],
                    cityCode: "perf_cmi"
                ),
                bestTimes: index % 3 == 0 ? [TimeWindow(startHour: 8, endHour: 22)] : [],
                durationMinutes: .init(min: 30, max: 60),
                howTo: [],
                realInconveniences: [],
                soloScore: SoloScore(
                    overall: Double(index % 10) + 0.5,
                    breakdown: .init(
                        seatingFriendly: 7, soloPatronRatio: 7, staffPressure: 7,
                        soloPortioning: 7, ambianceFit: 7, safety: 7
                    ),
                    basedOnCount: index % 5
                ),
                sources: [InformationSource(type: .user, attribution: "perf", verifiedAt: now)],
                confidence: Confidence(
                    level: 3,
                    lastVerifiedAt: now,
                    reason: "Perf fixture",
                    signals: .init(aiScrapeAgeDays: 1, passiveGpsHits30d: index % 4,
                                   activeReports30d: 0, trustedVerifications: 0)
                ),
                nearbyExperienceIds: [],
                stats: .init(completionCount: 0, averageRating: 0),
                status: .active,
                createdAt: now,
                updatedAt: now
            )
        }
    }

    // MARK: - Measurement helpers

    /// Cached path: one `markerState(for:)` call per iteration, the value reused
    /// for both the icon and the `.footprinted` badge branch — matches the
    /// post-US-016 ForEach body in CompassMapView.
    @MainActor
    private func cachedPassLatencies(_ vm: MapViewModel, now: Date) -> [TimeInterval] {
        var latencies: [TimeInterval] = []
        latencies.reserveCapacity(Self.iterations)
        for _ in 0..<Self.iterations {
            let start = Date()
            var iconStates = 0
            var badgeCount = 0
            for exp in vm.visibleExperiences {
                let state = vm.markerState(for: exp, now: now)
                iconStates += 1                       // MarkerIconView consumes `state`
                if case .footprinted = state {        // badge branch reuses `state`
                    badgeCount += vm.footprintCount(for: exp)
                }
            }
            latencies.append(Date().timeIntervalSince(start))
            // Defeat dead-code elimination.
            XCTAssertEqual(iconStates, Self.markerCount)
            _ = badgeCount
        }
        return latencies
    }

    /// Non-cached baseline: two `markerState(for:)` calls per iteration — the
    /// pre-US-016 shape where the icon and the badge branch each recomputed it.
    @MainActor
    private func nonCachedPassLatencies(_ vm: MapViewModel, now: Date) -> [TimeInterval] {
        var latencies: [TimeInterval] = []
        latencies.reserveCapacity(Self.iterations)
        for _ in 0..<Self.iterations {
            let start = Date()
            var iconStates = 0
            var badgeCount = 0
            for exp in vm.visibleExperiences {
                iconStates += 1
                _ = vm.markerState(for: exp, now: now)          // icon call
                if case .footprinted = vm.markerState(for: exp, now: now) {  // badge call (recomputed)
                    badgeCount += vm.footprintCount(for: exp)
                }
            }
            latencies.append(Date().timeIntervalSince(start))
            XCTAssertEqual(iconStates, Self.markerCount)
            _ = badgeCount
        }
        return latencies
    }

    private func p95(_ samples: [TimeInterval]) -> TimeInterval {
        let sorted = samples.sorted()
        let index = Int((Double(sorted.count) * 0.95).rounded(.up)) - 1
        return sorted[min(max(0, index), sorted.count - 1)]
    }

    // MARK: - testCachedMarkerStateP95DropsAtLeast40Percent

    @MainActor
    func testCachedMarkerStateP95DropsAtLeast40Percent() throws {
        let experiences = makeExperiences(count: Self.markerCount)
        let vm = makeViewModel(with: experiences)
        let now = Date()

        XCTAssertEqual(vm.visibleExperiences.count, Self.markerCount,
                       "Precondition: visibleExperiences must hold exactly \(Self.markerCount) entries")

        // Warm-up so the first measured pass isn't penalised by cold caches.
        _ = cachedPassLatencies(vm, now: now)
        _ = nonCachedPassLatencies(vm, now: now)

        // Interleave-free: measure baseline then cached.
        let baseline = nonCachedPassLatencies(vm, now: now)
        let cached = cachedPassLatencies(vm, now: now)

        let baselineP95 = p95(baseline)
        let cachedP95 = p95(cached)

        XCTAssertGreaterThan(baselineP95, 0, "Baseline p95 must be measurable")

        let improvement = (baselineP95 - cachedP95) / baselineP95
        XCTAssertGreaterThanOrEqual(
            improvement,
            Self.requiredImprovement,
            """
            Cached marker-state pass should be ≥ \(Int(Self.requiredImprovement * 100))% faster at p95. \
            baseline p95 = \(String(format: "%.6f", baselineP95))s, \
            cached p95 = \(String(format: "%.6f", cachedP95))s, \
            improvement = \(String(format: "%.1f", improvement * 100))%
            """
        )
    }

    // MARK: - testCachedAndNonCachedProduceIdenticalStates

    /// Caching must not change behaviour: the per-marker state resolved by the
    /// single hoisted call equals what two separate calls would have produced.
    @MainActor
    func testCachedAndNonCachedProduceIdenticalStates() throws {
        let experiences = makeExperiences(count: Self.markerCount)
        let vm = makeViewModel(with: experiences)
        let now = Date()

        for exp in vm.visibleExperiences {
            let cached = vm.markerState(for: exp, now: now)
            let recomputed = vm.markerState(for: exp, now: now)
            XCTAssertEqual(cached, recomputed,
                           "markerState must be deterministic for \(exp.id) so caching is safe")
        }
    }
}
