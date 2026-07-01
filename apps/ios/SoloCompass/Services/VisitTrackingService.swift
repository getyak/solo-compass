import Foundation
import Observation
import SwiftData
import UIKit
import os

/// Passive visit recorder for the Travel Archive (P1.1 #110).
///
/// Privacy contract — borrowed from `PresenceService` (Companion Mode):
/// - Runs **foreground only**. App backgrounding cancels every pending timer
///   so a stale dwell never lands as a phantom visit.
/// - Coordinates are stored locally on the device inside `VisitRecord`. The
///   blob never leaves the device unless the user explicitly enables Pro
///   cloud sync (not implemented in P1.1).
/// - Activation is implicit when the service is attached, but every entry
///   funnels through `LocationService.onRegionEnter`, which itself requires
///   the user to grant location permission via the existing onboarding flow.
///
/// How it works:
/// 1. On region enter, start a `dwellThreshold`-long Task (default 5 min).
/// 2. If the user exits before the timer fires, cancel the timer — no visit.
/// 3. If the timer fires (user stayed put), persist a `VisitRecord` with
///    a coord snapshot and dwell duration.
/// 4. On every backgrounding, drop all in-flight timers. We trade missing
///    a few legitimate visits for the much larger win of never logging a
///    phantom visit the user wasn't actually present for.
@MainActor
@Observable
public final class VisitTrackingService {

    public static let shared = VisitTrackingService(
        locationService: .shared,
        modelContainer: nil
    )

    /// Minimum continuous time inside a region before we record a visit.
    /// Adjustable so tests can drive it with sub-second values.
    public var dwellThreshold: TimeInterval = 5 * 60

    private let locationService: LocationService
    private var modelContainer: ModelContainer?

    /// Active dwell timers keyed by experience id. Entry creates one,
    /// exit cancels it, fire-time records the visit and clears the slot.
    private var pendingTimers: [String: Task<Void, Never>] = [:]
    /// Wall-clock instant we entered each region — needed because the
    /// timer's `Task.sleep` resolution is coarse and we want the real
    /// elapsed dwell, not the nominal threshold.
    private var entryTimestamps: [String: Date] = [:]

    private var backgroundObserverTask: Task<Void, Never>?
    private var attached: Bool = false

    private let log = OSLog(subsystem: "com.solocompass.app", category: "VisitTracking")

    public init(
        locationService: LocationService = .shared,
        modelContainer: ModelContainer?
    ) {
        self.locationService = locationService
        self.modelContainer = modelContainer
    }

    // MARK: - Activation

    /// Wire region enter/exit callbacks and start observing app lifecycle.
    /// Idempotent — safe to call multiple times.
    public func attach() {
        guard !attached else { return }
        attached = true

        // Chain existing closures so other subscribers (current or future)
        // are preserved — we never own the slot exclusively.
        let priorEnter = locationService.onRegionEnter
        let priorExit = locationService.onRegionExit

        locationService.onRegionEnter = { [weak self] identifier in
            priorEnter?(identifier)
            Task { @MainActor in
                self?.handleEnter(experienceId: identifier)
            }
        }
        locationService.onRegionExit = { [weak self] identifier in
            priorExit?(identifier)
            Task { @MainActor in
                self?.handleExit(experienceId: identifier)
            }
        }

        observeBackground()
    }

    /// Allow a SwiftData container to be injected after construction —
    /// the shared singleton is built before the app's container is ready.
    public func setModelContainer(_ container: ModelContainer) {
        self.modelContainer = container
    }

    // MARK: - Test seams

    /// Test-only hook to inject a region enter without touching CoreLocation.
    /// Mirrors what the LocationService closure would call.
    public func simulateRegionEnter(experienceId: String) {
        handleEnter(experienceId: experienceId)
    }

    /// Test-only hook to inject a region exit without touching CoreLocation.
    public func simulateRegionExit(experienceId: String) {
        handleExit(experienceId: experienceId)
    }

    /// Test-only: clear in-flight timers so each test starts hermetic.
    public func resetForTesting() {
        for (_, task) in pendingTimers { task.cancel() }
        pendingTimers.removeAll()
        entryTimestamps.removeAll()
    }

    // MARK: - Region lifecycle

    private func handleEnter(experienceId: String) {
        // Skip if we're already counting this region — re-entry events can fire
        // when GPS noise jiggles the boundary; the original timestamp wins.
        guard pendingTimers[experienceId] == nil else { return }

        let enteredAt = Date()
        entryTimestamps[experienceId] = enteredAt

        let threshold = dwellThreshold
        let timer = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(threshold * 1_000_000_000))
            guard !Task.isCancelled else { return }
            await self?.commitDwell(experienceId: experienceId, enteredAt: enteredAt)
        }
        pendingTimers[experienceId] = timer
    }

    private func handleExit(experienceId: String) {
        if let timer = pendingTimers[experienceId] {
            timer.cancel()
            pendingTimers[experienceId] = nil
        }
        entryTimestamps[experienceId] = nil
    }

    private func commitDwell(experienceId: String, enteredAt: Date) async {
        // Don't write if we got cancelled between sleep wake and now.
        guard pendingTimers[experienceId] != nil else { return }
        guard let container = modelContainer else {
            os_log("VisitTracking: no modelContainer attached — dropping visit %{public}@", log: log, type: .error, experienceId)
            pendingTimers[experienceId] = nil
            entryTimestamps[experienceId] = nil
            return
        }

        let dwellSeconds = Int(Date().timeIntervalSince(enteredAt))
        let coordSnap = encodeCurrentCoords()
        let record = VisitRecord(
            experienceId: experienceId,
            visitedAt: enteredAt,
            dwellSeconds: dwellSeconds,
            weatherCode: nil,
            coordSnapBlob: coordSnap
        )

        let context = ModelContext(container)
        context.insert(record)
        do {
            try context.save()
        } catch {
            os_log("VisitTracking: save failed %{public}@", log: log, type: .error, String(describing: error))
        }

        pendingTimers[experienceId] = nil
        entryTimestamps[experienceId] = nil
    }

    private func encodeCurrentCoords() -> Data? {
        guard let loc = locationService.currentLocation else { return nil }
        // GeoJSON convention: [lon, lat]
        return VisitRecord.encodeCoords([loc.coordinate.longitude, loc.coordinate.latitude])
    }

    // MARK: - Background observer

    private func observeBackground() {
        backgroundObserverTask = Task { @MainActor [weak self] in
            let nc = NotificationCenter.default
            for await _ in nc.notifications(named: UIApplication.didEnterBackgroundNotification) {
                self?.dropAllPending()
            }
        }
    }

    private func dropAllPending() {
        for (_, task) in pendingTimers { task.cancel() }
        pendingTimers.removeAll()
        entryTimestamps.removeAll()
    }
}
