import XCTest
import SwiftData
import CoreLocation
@testable import SoloCompass

/// Tests for `VisitTrackingService` (P1.1 #110).
///
/// The service uses a real `Task.sleep` to wait out the dwell threshold, so
/// tests inject a sub-second threshold and `await` a real (but short) sleep
/// before asserting. Each test builds a fresh in-memory ModelContainer to
/// keep state hermetic.
@MainActor
final class VisitTrackingServiceTests: XCTestCase {

    // MARK: - Helpers

    /// Build a fresh in-memory container holding only the models this
    /// service touches — keeps the test boot fast and isolated.
    private func makeContainer() throws -> ModelContainer {
        let config = ModelConfiguration("VisitTrackingTests", isStoredInMemoryOnly: true)
        return try ModelContainer(for: VisitRecord.self, configurations: config)
    }

    private func makeService(threshold: TimeInterval = 0.15) throws -> (VisitTrackingService, ModelContainer) {
        let container = try makeContainer()
        let service = VisitTrackingService(
            locationService: .shared,
            modelContainer: container
        )
        service.dwellThreshold = threshold
        return (service, container)
    }

    private func fetchVisits(in container: ModelContainer, experienceId: String) throws -> [VisitRecord] {
        let context = ModelContext(container)
        let predicate = #Predicate<VisitRecord> { $0.experienceId == experienceId }
        return try context.fetch(FetchDescriptor<VisitRecord>(predicate: predicate))
    }

    // MARK: - Happy path

    func testEnterAndDwellPastThresholdWritesVisitRecord() async throws {
        let (service, container) = try makeService(threshold: 0.10)

        service.simulateRegionEnter(experienceId: "exp_test_happy")
        // Wait past the threshold + a small safety margin so commitDwell lands.
        try await Task.sleep(nanoseconds: 250_000_000)

        let visits = try fetchVisits(in: container, experienceId: "exp_test_happy")
        XCTAssertEqual(visits.count, 1, "a single sustained dwell must record exactly one visit")
        XCTAssertGreaterThanOrEqual(try XCTUnwrap(visits.first).dwellSeconds, 0)
    }

    // MARK: - Cancellation

    func testEarlyExitBeforeThresholdDoesNotWriteVisit() async throws {
        let (service, container) = try makeService(threshold: 0.30)

        service.simulateRegionEnter(experienceId: "exp_test_brief")
        // Exit before the timer fires.
        try await Task.sleep(nanoseconds: 50_000_000)
        service.simulateRegionExit(experienceId: "exp_test_brief")

        // Wait well past the original threshold to prove no late write.
        try await Task.sleep(nanoseconds: 400_000_000)

        let visits = try fetchVisits(in: container, experienceId: "exp_test_brief")
        XCTAssertEqual(visits.count, 0, "exit before dwell threshold must not produce a VisitRecord")
    }

    // MARK: - GPS noise / re-entry

    func testReentryWhileTimerActiveIsIgnored() async throws {
        let (service, container) = try makeService(threshold: 0.15)

        service.simulateRegionEnter(experienceId: "exp_test_jitter")
        // GPS noise — same region fires again before the dwell completes.
        try await Task.sleep(nanoseconds: 50_000_000)
        service.simulateRegionEnter(experienceId: "exp_test_jitter")

        try await Task.sleep(nanoseconds: 250_000_000)

        let visits = try fetchVisits(in: container, experienceId: "exp_test_jitter")
        XCTAssertEqual(visits.count, 1, "re-entry while timer is alive must collapse to one visit")
    }

    // MARK: - Multiple regions in parallel

    func testTwoSimultaneousRegionsBothRecordIndependently() async throws {
        let (service, container) = try makeService(threshold: 0.10)

        service.simulateRegionEnter(experienceId: "exp_test_a")
        service.simulateRegionEnter(experienceId: "exp_test_b")
        try await Task.sleep(nanoseconds: 250_000_000)

        let a = try fetchVisits(in: container, experienceId: "exp_test_a")
        let b = try fetchVisits(in: container, experienceId: "exp_test_b")
        XCTAssertEqual(a.count, 1)
        XCTAssertEqual(b.count, 1)
    }

    // MARK: - Exit cancels timer cleanly

    func testExitDuringDwellCancelsAndAllowsFreshEnterLater() async throws {
        let (service, container) = try makeService(threshold: 0.15)

        service.simulateRegionEnter(experienceId: "exp_test_round_trip")
        try await Task.sleep(nanoseconds: 50_000_000)
        service.simulateRegionExit(experienceId: "exp_test_round_trip")

        // Now legitimately revisit and stay.
        try await Task.sleep(nanoseconds: 50_000_000)
        service.simulateRegionEnter(experienceId: "exp_test_round_trip")
        try await Task.sleep(nanoseconds: 250_000_000)

        let visits = try fetchVisits(in: container, experienceId: "exp_test_round_trip")
        XCTAssertEqual(visits.count, 1, "second sustained dwell after a cancelled one must record exactly one visit")
    }

    // MARK: - Resilience without container

    func testMissingModelContainerDoesNotCrash() async throws {
        let service = VisitTrackingService(
            locationService: .shared,
            modelContainer: nil
        )
        service.dwellThreshold = 0.10

        service.simulateRegionEnter(experienceId: "exp_test_orphan")
        // Just need to survive past the threshold without throwing.
        try await Task.sleep(nanoseconds: 250_000_000)

        // Reaching here without an exception is the assertion. Add an
        // explicit XCTAssert to make the intent obvious to readers.
        XCTAssertTrue(true, "service must drop visits silently when no container is attached")
    }

    // MARK: - Reset hook

    func testResetForTestingClearsInflightTimers() async throws {
        let (service, container) = try makeService(threshold: 0.30)

        service.simulateRegionEnter(experienceId: "exp_test_reset_a")
        service.simulateRegionEnter(experienceId: "exp_test_reset_b")
        service.resetForTesting()

        try await Task.sleep(nanoseconds: 400_000_000)

        let a = try fetchVisits(in: container, experienceId: "exp_test_reset_a")
        let b = try fetchVisits(in: container, experienceId: "exp_test_reset_b")
        XCTAssertEqual(a.count, 0)
        XCTAssertEqual(b.count, 0)
    }
}
