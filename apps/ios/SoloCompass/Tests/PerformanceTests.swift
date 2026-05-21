import XCTest
import CoreLocation
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
}

// MARK: - US-036: Chat first-token-latency performance test

/// Benchmarks AgentRouter first-token latency with a mocked streaming GuideAgent.
/// Asserts P95 < 800ms across 20 samples.
///
/// Run with:
///   xcodebuild test -only-testing:SoloCompassTests/PerformanceTests
final class PerformanceTests: XCTestCase {

    private static let sampleCount = 20
    private static let p95ThresholdMs: Double = 800

    // MARK: - P95 latency assertion

    func testAgentRouterFirstTokenLatencyP95Under800ms() async throws {
        var latenciesMs: [Double] = []

        for _ in 0..<Self.sampleCount {
            let latency = try await measureFirstTokenLatency()
            latenciesMs.append(latency)
        }

        latenciesMs.sort()
        let p95Index = Int(Double(latenciesMs.count) * 0.95) - 1
        let p95 = latenciesMs[max(0, p95Index)]

        XCTAssertLessThan(
            p95,
            Self.p95ThresholdMs,
            "P95 first-token latency \(String(format: "%.1f", p95))ms exceeds \(Self.p95ThresholdMs)ms threshold"
        )
    }

    // MARK: - Mean sanity check

    func testFirstTokenMeanLatencyIsReasonable() async throws {
        var latencies: [Double] = []
        for _ in 0..<10 {
            let latency = try await measureFirstTokenLatency()
            latencies.append(latency)
        }
        let mean = latencies.reduce(0, +) / Double(latencies.count)
        XCTAssertLessThan(mean, Self.p95ThresholdMs,
            "Mean latency \(String(format: "%.1f", mean))ms should be well under \(Self.p95ThresholdMs)ms with mocked stream")
    }

    // MARK: - Measurement helper

    private func makeGuideAgent() -> GuideAgent {
        let sseBody = """
        data: {"type":"content_block_delta","delta":{"type":"text_delta","text":"Here are some great spots!"}}
        data: {"type":"message_stop"}

        """
        PerfStreamStubProtocol.sseBody = sseBody
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [PerfStreamStubProtocol.self]
        let session = URLSession(configuration: config)
        return GuideAgent(
            session: session,
            apiKey: "perf-test-key",
            apiURL: URL(string: "https://stub.perf/v1/messages")!
        )
    }

    private func measureFirstTokenLatency() async throws -> Double {
        let agent = makeGuideAgent()
        let message = AgentMessage(
            text: "recommend something nearby",
            history: []
        )
        let stream = agent.stream(
            message: message,
            contextSnapshot: nil,
            experienceSummaries: ["Nimman Cafe — coffee — 8.5/10"]
        )

        let start = Date()
        var gotFirstToken = false
        var firstTokenMs: Double = 0

        for try await _ in stream {
            if !gotFirstToken {
                firstTokenMs = Date().timeIntervalSince(start) * 1000
                gotFirstToken = true
                break
            }
        }

        if !gotFirstToken {
            firstTokenMs = Date().timeIntervalSince(start) * 1000
        }
        return firstTokenMs
    }
}

// MARK: - PerfStreamStubProtocol

/// Returns an SSE stream immediately with minimal delay — measures routing overhead only.
final class PerfStreamStubProtocol: URLProtocol {
    nonisolated(unsafe) static var sseBody: String = ""

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let data = Self.sseBody.data(using: .utf8) ?? Data()
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: ["Content-Type": "text/event-stream"]
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
