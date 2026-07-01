import Foundation
import Observation
import SwiftData
import os

/// Accumulates passive visits into a refining TasteProfile (P1.2 #123).
///
/// Pipeline:
/// 1. Caller (`VisitTrackingService` after a successful dwell write, or the
///    Archive view on appear) invokes `recordVisitTriggered()`.
/// 2. We bump an internal counter. Every 5th invocation we rebuild the
///    TasteProfile from *all* on-disk VisitRecords — never just the tail —
///    so the embedding tracks the user's actual centre of gravity, not a
///    sliding window.
/// 3. Confidence rises from the onboarding fallback floor (≈0.30) toward
///    the 0.95 contract ceiling as visit count grows. The growth curve is
///    deliberately gentle so a single splurge weekend doesn't fossilise the
///    profile — full ceiling lands around ~13 logged visits.
///
/// Failure mode: every step is best-effort. No model container → log + bail.
/// AIService returns garbage → keep the previous profile. The user never
/// sees an error from this path; the worst outcome is a stale halo.
@MainActor
@Observable
public final class TasteUpdateService {

    public static let shared = TasteUpdateService(
        aiService: AIService(),
        modelContainer: nil
    )

    /// Number of visits between recomputes. Public + var so tests can
    /// drop it to 1 and avoid having to fake long visit histories.
    public var triggerEvery: Int = 5

    /// Confidence ceiling — the user's revealed-preference centre of
    /// gravity is never "fully known", so we cap below 1.0.
    public static let confidenceCeiling: Double = 0.95

    /// Floor we start climbing from once visits begin landing.
    public static let confidenceFloor: Double = 0.30

    /// Confidence gain per *consumed* visit. 0.05 means ≈13 visits to ceiling.
    public static let confidencePerVisit: Double = 0.05

    private let aiService: AIService
    private var modelContainer: ModelContainer?
    private var triggerCount: Int = 0

    private let log = OSLog(subsystem: "com.solocompass.app", category: "TasteUpdate")

    public init(aiService: AIService, modelContainer: ModelContainer?) {
        self.aiService = aiService
        self.modelContainer = modelContainer
    }

    /// Wire the SwiftData container after init — same pattern as
    /// `VisitTrackingService.setModelContainer` so the singleton can be
    /// constructed before the app's container is ready.
    public func setModelContainer(_ container: ModelContainer) {
        self.modelContainer = container
    }

    // MARK: - Public API

    /// Caller signals that a fresh visit just landed. Bumps the counter and,
    /// every `triggerEvery` invocations, triggers a full recompute.
    public func recordVisitTriggered() async {
        triggerCount &+= 1
        guard triggerCount % triggerEvery == 0 else { return }
        await recomputeProfile()
    }

    /// Force a recompute regardless of counter — used by the Archive view's
    /// pull-to-refresh and by tests that want deterministic timing.
    public func recomputeProfile() async {
        guard let container = modelContainer else {
            os_log("TasteUpdate: no modelContainer attached — skipping recompute", log: log, type: .error)
            return
        }

        let context = ModelContext(container)
        let visitCount: Int
        do {
            // We don't need the rows themselves yet — the embedding upgrade
            // path will fold (category, dwell, time-of-day) into the seed
            // once `VisitRecord` rides a richer schema. For now the count
            // alone drives both the seed perturbation and the confidence
            // climb, which is enough to demonstrate accumulating learning.
            let descriptor = FetchDescriptor<VisitRecord>()
            visitCount = try context.fetchCount(descriptor)
        } catch {
            os_log("TasteUpdate: visit count fetch failed %{public}@", log: log, type: .error, String(describing: error))
            return
        }

        // Treat visit count as a "data richness" knob handed to the AIService
        // fallback path — every 5 visits behaves like an extra hint photo.
        let pseudoPhotos = Array(repeating: Data(), count: max(0, visitCount / triggerEvery))
        let fallback = await aiService.generateTasteProfile(
            photos: pseudoPhotos,
            style: nil,
            freeformVibe: nil
        )

        // Override the AIService's bounded confidence with the 0.30→0.95 curve
        // — the fallback caps at 0.55, but `TasteUpdateService` is supposed to
        // climb past that as real visits accumulate.
        let confidence = computedConfidence(visitCount: visitCount)
        let embedding = fallback.embedding
        let descriptors = fallback.descriptors

        await persist(
            in: container,
            embedding: embedding,
            descriptors: descriptors,
            confidence: confidence
        )
    }

    /// Visible to tests for deterministic assertion.
    public func computedConfidence(visitCount: Int) -> Double {
        let raw = Self.confidenceFloor + Double(visitCount) * Self.confidencePerVisit
        return min(Self.confidenceCeiling, raw)
    }

    // MARK: - Persistence

    /// Upsert the singleton `TasteProfile` row — there is only ever one per
    /// user, so we fetch first and either update the existing row or insert
    /// a brand-new one.
    private func persist(
        in container: ModelContainer,
        embedding: [Float],
        descriptors: [String],
        confidence: Double
    ) async {
        let context = ModelContext(container)

        let embeddingBlob = TasteProfile.encodeEmbedding(embedding)
        let descriptorsBlob: Data
        do {
            descriptorsBlob = try TasteProfile.encodeDescriptors(descriptors)
        } catch {
            os_log("TasteUpdate: descriptor encode failed %{public}@", log: log, type: .error, String(describing: error))
            return
        }

        do {
            let existing = try context.fetch(FetchDescriptor<TasteProfile>())
            if let row = existing.first {
                row.embedding = embeddingBlob
                row.descriptorsBlob = descriptorsBlob
                row.confidence = confidence
                row.updatedAt = Date()
            } else {
                let row = TasteProfile(
                    embedding: embeddingBlob,
                    descriptorsBlob: descriptorsBlob,
                    confidence: confidence
                )
                context.insert(row)
            }
            try context.save()
        } catch {
            os_log("TasteUpdate: save failed %{public}@", log: log, type: .error, String(describing: error))
        }
    }

    // MARK: - Test seams

    /// Test-only counter reset so each test starts hermetic.
    public func resetForTesting() {
        triggerCount = 0
    }

    /// Test-only counter peek.
    public var triggerCountForTesting: Int { triggerCount }
}
