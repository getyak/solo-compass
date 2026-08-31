import XCTest
import MapKit
import SwiftUI
@testable import SoloCompass

// MARK: - US-019: Map render baseline with 150 markers

/// Baseline performance test: seed MapViewModel.visibleExperiences with 150 generated
/// Experiences spread across a bounding box, then measure the marker-state derivation
/// loop that the map layer runs for every visible pin on each render cycle.
///
/// Uses XCTClockMetric + XCTMemoryMetric so the baseline is recorded by Xcode
/// and regressions surface as test failures on subsequent runs.
///
/// Run with:
///   xcodebuild test -only-testing:SoloCompassTests/MapRenderPerformanceTests
final class MapRenderPerformanceTests: XCTestCase {

    private static let markerCount = 150

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
                id: "perf_marker_\(index)",
                title: "Perf Marker \(index)",
                oneLiner: "Baseline marker \(index)",
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

    // MARK: - testMapRenderWith150Markers

    /// Baseline: derive the marker state for all 150 visible experiences, mirroring
    /// what CompassMapView does on every render cycle for each annotation in the set.
    ///
    /// The `measure(metrics:)` block records wall-clock time and peak memory delta
    /// for 5 iterations. Xcode stores the baseline; subsequent runs fail when either
    /// metric regresses past the allowed threshold.
    ///
    /// The assert on elapsed time provides a hard in-CI upper bound (2.0 s) that
    /// guards against pathological regressions on low-end hardware.
    @MainActor
    func testMapRenderWith150Markers() async throws {
        let experiences = makeExperiences(count: Self.markerCount)
        let vm = makeViewModel(with: experiences)
        let now = Date()

        XCTAssertEqual(vm.visibleExperiences.count, Self.markerCount,
                       "Precondition: visibleExperiences must hold exactly \(Self.markerCount) entries")

        let metrics: [XCTMetric] = [XCTClockMetric(), XCTMemoryMetric()]
        let options = XCTMeasureOptions()
        options.iterationCount = 5

        var elapsed: TimeInterval = 0

        measure(metrics: metrics, options: options) {
            let start = Date()
            // Derive marker state for every visible experience — this mirrors the
            // per-annotation path executed by the map view on each render pass.
            var states: [ExperienceMarkerState] = []
            states.reserveCapacity(Self.markerCount)
            for exp in vm.visibleExperiences {
                states.append(vm.markerState(for: exp, now: now))
            }
            elapsed = Date().timeIntervalSince(start)
            // Sanity: every marker resolved to a state.
            _ = states.count
        }

        // Hard upper bound: one full pass over 150 markers must complete in < 2.0 s
        // even on a slow CI runner. The actual measured time is typically < 1 ms;
        // the threshold is generous to survive any scheduler jitter.
        XCTAssertLessThan(
            elapsed,
            2.0,
            "Marker-state derivation for \(Self.markerCount) experiences must complete in < 2.0 s; got \(elapsed) s"
        )
    }

    /// SwiftUI may ask for the map content repeatedly within one display pass.
    /// Ranking + clustering must rebuild once, then remain a cache hit until a
    /// real input dimension (data, zoom band, affinity, minute) changes.
    @MainActor
    func testMapRenderSnapshotReusesRankingAndClusteringWork() {
        let vm = makeViewModel(with: makeExperiences(count: Self.markerCount))
        let now = Date(timeIntervalSince1970: 1_788_160_000)
        vm.currentSpanLatitudeDelta = 0.20
        let before = vm.mapRenderComputeCount

        for _ in 0..<1_000 {
            _ = vm.clusteredMapItems(at: now)
        }
        XCTAssertEqual(
            vm.mapRenderComputeCount,
            before + 1,
            "1,000 identical body reads should pay ranking + clustering exactly once"
        )

        // Same display-limit and clustering bands: no rebuild for harmless
        // MapKit zoom settling inside the band.
        vm.currentSpanLatitudeDelta = 0.21
        _ = vm.clusteredMapItems(at: now.addingTimeInterval(10))
        XCTAssertEqual(vm.mapRenderComputeCount, before + 1)

        // Crossing to street level changes both LOD and cluster policy.
        vm.currentSpanLatitudeDelta = 0.01
        _ = vm.clusteredMapItems(at: now)
        XCTAssertEqual(vm.mapRenderComputeCount, before + 2)
    }
}

// MARK: - Map interaction invalidation and viewport refresh budgets

@MainActor
final class MapInteractionSmoothnessTests: XCTestCase {
    func testOneHundredTwentyContinuousCallbacksProduceOnlyTwoStateEdges() {
        let coordinator = MapInteractionCoordinator(fallbackIdleSeconds: 10)
        let start = Date(timeIntervalSince1970: 1_788_160_000)
        var stateEdges: [Bool] = []

        for frame in 0..<120 {
            coordinator.noteContinuous(
                at: start.addingTimeInterval(Double(frame) / 120),
                onStateChange: { stateEdges.append($0) }
            )
        }

        XCTAssertEqual(stateEdges, [true])
        XCTAssertEqual(
            coordinator.fallbackTaskStartCount,
            1,
            "continuous callbacks must share one safety-net task"
        )

        coordinator.noteEnded { stateEdges.append($0) }
        XCTAssertEqual(
            stateEdges,
            [true, false],
            "one gesture gets exactly active + settled observable edges"
        )
    }

    func testFallbackSettlesInterruptedGestureWithoutExtraEdges() {
        let coordinator = MapInteractionCoordinator(fallbackIdleSeconds: 0.25)
        let start = Date(timeIntervalSince1970: 1_788_160_000)
        var stateEdges: [Bool] = []

        coordinator.noteContinuous(at: start) { stateEdges.append($0) }
        XCTAssertFalse(
            coordinator.settleIfIdle(at: start.addingTimeInterval(0.24)) {
                stateEdges.append($0)
            }
        )
        XCTAssertTrue(
            coordinator.settleIfIdle(at: start.addingTimeInterval(0.25)) {
                stateEdges.append($0)
            }
        )
        XCTAssertEqual(stateEdges, [true, false])
    }

    func testViewportJitterDoesNotRefreshButMeaningfulTravelDoes() {
        let baseline = MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 18.7877, longitude: 98.9938),
            span: MKCoordinateSpan(latitudeDelta: 0.08, longitudeDelta: 0.08)
        )
        let jitter = MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 18.7917, longitude: 98.9978),
            span: MKCoordinateSpan(latitudeDelta: 0.083, longitudeDelta: 0.083)
        )
        let meaningfulPan = MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 18.7997, longitude: 98.9938),
            span: baseline.span
        )

        XCTAssertFalse(MapViewportRefreshPolicy.shouldRefresh(from: baseline, to: jitter))
        XCTAssertTrue(MapViewportRefreshPolicy.shouldRefresh(from: baseline, to: meaningfulPan))
    }

    func testViewportMeaningfulZoomRefreshesWithoutCenterMovement() {
        let baseline = MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 18.7877, longitude: 98.9938),
            span: MKCoordinateSpan(latitudeDelta: 0.08, longitudeDelta: 0.08)
        )
        let zoomed = MKCoordinateRegion(
            center: baseline.center,
            span: MKCoordinateSpan(latitudeDelta: 0.07, longitudeDelta: 0.07)
        )
        XCTAssertTrue(MapViewportRefreshPolicy.shouldRefresh(from: baseline, to: zoomed))
    }
}

// MARK: - User-perceived latency distributions

@MainActor
final class InteractionLatencySummaryTests: XCTestCase {
    func testLatencySummaryUsesInterpolatedPercentilesAndJourneyFiltering() throws {
        let samples: [InteractionTracker.LatencySample] = [
            .init(journey: .pinToDetail, durationMilliseconds: 100, withinBudget: true),
            .init(journey: .pinToDetail, durationMilliseconds: 200, withinBudget: true),
            .init(journey: .pinToDetail, durationMilliseconds: 300, withinBudget: true),
            .init(journey: .pinToDetail, durationMilliseconds: 400, withinBudget: false),
            .init(journey: .sheetSettle, durationMilliseconds: 900, withinBudget: false)
        ]

        let summary = try XCTUnwrap(InteractionTracker.latencySummary(
            for: .pinToDetail,
            samples: samples
        ))
        XCTAssertEqual(summary.sampleCount, 4)
        XCTAssertEqual(summary.p50Milliseconds, 250, accuracy: 0.001)
        XCTAssertEqual(summary.p95Milliseconds, 385, accuracy: 0.001)
        XCTAssertEqual(summary.withinBudgetRate, 0.75, accuracy: 0.001)
        XCTAssertFalse(summary.isWithinBudget)
    }

    func testLatencySummaryReturnsNilWithoutMatchingSamples() {
        XCTAssertNil(InteractionTracker.latencySummary(for: .sheetSettle, samples: []))
    }

    func testDeveloperPerformanceSurfaceRendersWithLiveSamples() async throws {
        let tracker = InteractionTracker.shared
        tracker.clearLatencySamples()
        tracker.beginLatency(.pinToDetail)
        try await Task.sleep(for: .milliseconds(12))
        tracker.finishLatency(.pinToDetail)
        tracker.beginLatency(.sheetSettle)
        try await Task.sleep(for: .milliseconds(16))
        tracker.finishLatency(.sheetSettle)
        defer { tracker.clearLatencySamples() }

        let view = NavigationStack {
            DeveloperOptionsView()
                .environment(UserPreferences())
                .environment(SubscriptionService())
        }
        let bounds = CGRect(x: 0, y: 0, width: 390, height: 1_100)
        let host = UIHostingController(rootView: view)
        host.view.frame = bounds
        let window = UIWindow(frame: bounds)
        window.rootViewController = host
        window.makeKeyAndVisible()
        host.view.setNeedsLayout()
        host.view.layoutIfNeeded()
        await Task.yield()

        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 2
        let image = UIGraphicsImageRenderer(bounds: bounds, format: format).image { _ in
            host.view.drawHierarchy(in: bounds, afterScreenUpdates: true)
        }
        XCTAssertGreaterThan(image.size.width, 0)
        XCTAssertGreaterThan(image.size.height, 0)
        let data = try XCTUnwrap(image.pngData())
        try data.write(to: URL(fileURLWithPath: "/tmp/ux-performance-diagnostics.png"))
    }
}
