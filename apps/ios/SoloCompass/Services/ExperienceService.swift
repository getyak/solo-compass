import Foundation
import CoreLocation
import Observation
import SwiftData

/// Thin @Observable facade over `ExperienceRepository`. View models and
/// views observe `allExperiences` / `filteredExperiences` exactly as
/// before; mutations go through here, get persisted to SwiftData, and
/// the in-memory caches are refreshed.
///
/// On init we import the bundled seed once (idempotent) so first-launch
/// users get the curated Chiang Mai entries without any explicit step.
@Observable
@MainActor
public final class ExperienceService {
    public private(set) var allExperiences: [Experience]
    public private(set) var filteredExperiences: [Experience]

    private let repository: ExperienceRepository

    /// Production init — wires up the shared SwiftData container and
    /// imports the seed if needed.
    public init() {
        let repo = ExperienceRepository()
        repo.importSeedIfNeeded()
        let initial = repo.allExperiences()
        let resolved = initial.isEmpty ? Self.hardcodedSeed : initial
        self.repository = repo
        self.allExperiences = resolved
        self.filteredExperiences = resolved
    }

    /// Test/preview init. Pass `seed:` to load an in-memory list and
    /// skip both bundle and SwiftData reads, or pass `repository:` to
    /// override the persistence layer with an in-memory container.
    public init(seed: [Experience]? = nil, repository: ExperienceRepository? = nil) {
        if let seed {
            let repo = repository ?? ExperienceRepository(
                context: ModelContext(SoloCompassModelContainer.makeInMemory()),
                preferences: nil
            )
            self.repository = repo
            self.allExperiences = seed
            self.filteredExperiences = seed
            return
        }
        let repo = repository ?? ExperienceRepository()
        repo.importSeedIfNeeded()
        let initial = repo.allExperiences()
        let resolved = initial.isEmpty ? Self.hardcodedSeed : initial
        self.repository = repo
        self.allExperiences = resolved
        self.filteredExperiences = resolved
    }

    // MARK: - Reload from store

    /// Re-pull from the repo and refresh the @Observable mirror. Call
    /// after mutations that may have inserted/removed rows.
    public func reload() {
        let fresh = repository.allExperiences()
        self.allExperiences = fresh.isEmpty ? Self.hardcodedSeed : fresh
        self.filteredExperiences = self.allExperiences
    }

    // MARK: - Filtering

    public func filter(by category: ExperienceCategory?, near location: CLLocationCoordinate2D?, maxDistance: Double) {
        filteredExperiences = allExperiences.filter { exp in
            if let category, exp.category != category { return false }
            if let location {
                guard let coord = exp.coordinate else { return false }
                let d = distanceMeters(from: location, to: coord)
                if d > maxDistance * 1000 { return false }
            }
            return true
        }
    }

    public func getExperiences(near location: CLLocationCoordinate2D, radiusKm: Double) -> [Experience] {
        let radiusMeters = radiusKm * 1000
        return allExperiences
            .compactMap { exp -> (Experience, Double)? in
                guard let coord = exp.coordinate else { return nil }
                return (exp, distanceMeters(from: location, to: coord))
            }
            .filter { $0.1 <= radiusMeters }
            .sorted { $0.1 < $1.1 }
            .map { $0.0 }
    }

    public func getExperience(id: String) -> Experience? {
        allExperiences.first(where: { $0.id == id })
    }

    public func getBestNowExperiences(at date: Date, near location: CLLocationCoordinate2D) -> [Experience] {
        getExperiences(near: location, radiusKm: 5.0).filter { $0.isBestNow(at: date) }
    }

    // MARK: - Mutations — write through repo

    public func markCompleted(_ id: String) {
        // Bump in-memory stats so observers see it immediately. The
        // authoritative count comes from UserCompletionRecord rows
        // (US-009 wires read paths through the repo). Bumping
        // preserves the previous UX where the detail view reflects
        // the action right away.
        guard let idx = allExperiences.firstIndex(where: { $0.id == id }) else { return }
        let old = allExperiences[idx]
        let newStats = Experience.Stats(
            completionCount: old.stats.completionCount + 1,
            averageRating: old.stats.averageRating,
            lastCompletedAt: Date()
        )
        let updated = old.copy(stats: newStats, updatedAt: Date())
        allExperiences[idx] = updated
        if let firstIdx = filteredExperiences.firstIndex(where: { $0.id == id }) {
            filteredExperiences[firstIdx] = updated
        }
        repository.update(updated)
        repository.recordCompletion(experienceId: id)
    }

    public func toggleFavorite(_ id: String, in preferences: UserPreferences) {
        preferences.toggleFavorite(id)
    }

    /// Merge a batch of newly generated experiences. Persists through
    /// the repo and refreshes the @Observable mirrors.
    @discardableResult
    public func appendGenerated(_ generated: [Experience]) -> Int {
        let added = repository.appendGenerated(generated)
        if added > 0 {
            reload()
        }
        return added
    }

    // MARK: - Repo accessor

    /// Read-only access to the underlying repository for callers that
    /// need queries beyond the @Observable mirror (e.g. completion
    /// counts, favorite list).
    public var repo: ExperienceRepository { repository }

    // MARK: - Distance helper (Haversine, mirrors core/geo.ts)

    private func distanceMeters(from a: CLLocationCoordinate2D, to b: CLLocationCoordinate2D) -> Double {
        let la = CLLocation(latitude: a.latitude, longitude: a.longitude)
        let lb = CLLocation(latitude: b.latitude, longitude: b.longitude)
        return la.distance(from: lb)
    }
}

// MARK: - Hardcoded seed (Chiang Mai)

extension ExperienceService {
    static let hardcodedSeed: [Experience] = {
        let now = Date()
        let recent = Calendar.current.date(byAdding: .day, value: -7, to: now) ?? now

        func conf(level: Int, reason: String) -> Confidence {
            Confidence(
                level: level,
                lastVerifiedAt: recent,
                reason: reason,
                signals: .init(aiScrapeAgeDays: 7, passiveGpsHits30d: 24, activeReports30d: 8, trustedVerifications: 1)
            )
        }

        return [
            Experience(
                id: "exp_cmi_suan_dok_sunset",
                title: "Watch the sunset paint the white stupas at Wat Suan Dok",
                oneLiner: "The royal cemetery's white chedis catch fire in the last 30 minutes of daylight.",
                whyItMatters: "Most travelers visit temples in midday glare. At sunset, the courtyard empties and the white stupas blaze gold against Doi Suthep behind them. The light shifts every minute. Bring nothing but yourself and time to sit on the stone steps.",
                category: .culture,
                location: ExperienceLocation(
                    coordinates: [98.9692, 18.7892], cityCode: "cmi",
                    addressHint: "Suthep, Mueang Chiang Mai",
                    placeNameLocal: "วัดสวนดอก",
                    placeNameRomanized: "Wat Suan Dok"
                ),
                bestTimes: [TimeWindow(startHour: 17, endHour: 19, note: "30 min before sunset")],
                durationMinutes: .init(min: 30, max: 60),
                howTo: [
                    HowToStep(order: 1, text: "Arrive 30 minutes before local sunset."),
                    HowToStep(order: 2, text: "Enter the chedi courtyard on the west side."),
                    HowToStep(order: 3, text: "Sit on the steps facing Doi Suthep."),
                    HowToStep(order: 4, text: "Stay through full dark — lights come on."),
                ],
                realInconveniences: [
                    RealInconvenience(category: .etiquette, text: "Cover shoulders and knees. Remove shoes inside the chapel."),
                    RealInconvenience(category: .crowds, text: "Tour buses occasionally arrive at sunset; weekdays are quieter."),
                ],
                soloScore: SoloScore(
                    overall: 9.2,
                    breakdown: .init(seatingFriendly: 9, soloPatronRatio: 8, staffPressure: 10, soloPortioning: 10, ambianceFit: 9, safety: 9),
                    hint: "Sit anywhere, no one will bother you.",
                    basedOnCount: 14
                ),
                sources: [
                    InformationSource(type: .wikivoyage, url: URL(string: "https://en.wikivoyage.org/wiki/Chiang_Mai"), attribution: "Wikivoyage", verifiedAt: recent),
                ],
                confidence: conf(level: 4, reason: "Verified by 1 trusted reporter, 8 active reports in last 30d"),
                nearbyExperienceIds: ["exp_cmi_nimman_coffee"],
                stats: .init(completionCount: 47, averageRating: 4.7),
                status: .active,
                createdAt: recent, updatedAt: recent
            ),
            Experience(
                id: "exp_cmi_nimman_coffee",
                title: "Find the hidden coffee roaster in a Nimman back alley",
                oneLiner: "A two-table roastery behind an unmarked wooden door, run by a former Bangkok barista.",
                whyItMatters: "Nimmanhaemin's main strip is full of Instagram cafés. One soi over, in a converted shophouse with no English signage, beans are roasted three mornings a week. The owner pours one pour-over at a time. There's a single bar seat. You'll talk to him or watch the kettle in silence.",
                category: .coffee,
                location: ExperienceLocation(
                    coordinates: [98.9683, 18.8019], cityCode: "cmi",
                    addressHint: "Soi 7, Nimmanhaemin Rd",
                    placeNameRomanized: "Nimman Roasters"
                ),
                bestTimes: [TimeWindow(startHour: 8, endHour: 11, note: "Roasting mornings: Tue/Thu/Sat")],
                durationMinutes: .init(min: 30, max: 60),
                howTo: [
                    HowToStep(order: 1, text: "Enter Nimman Soi 7 from the east."),
                    HowToStep(order: 2, text: "Look for the unmarked teak door, third on the right."),
                    HowToStep(order: 3, text: "Order the single-origin pour-over."),
                ],
                realInconveniences: [
                    RealInconvenience(category: .logistics, text: "Closed unpredictably. If the door's locked, come back tomorrow."),
                    RealInconvenience(category: .crowds, text: "Only two seats. If both are taken, you wait."),
                ],
                soloScore: SoloScore(
                    overall: 9.5,
                    breakdown: .init(seatingFriendly: 10, soloPatronRatio: 10, staffPressure: 9, soloPortioning: 10, ambianceFit: 9, safety: 10),
                    hint: "Bar seat is built for one. Bring a book.",
                    basedOnCount: 9
                ),
                sources: [
                    InformationSource(type: .reddit, url: URL(string: "https://reddit.com/r/chiangmai"), attribution: "u/cm_local", verifiedAt: recent),
                ],
                confidence: conf(level: 3, reason: "6 active reports, 22 GPS hits in 30d"),
                nearbyExperienceIds: ["exp_cmi_suan_dok_sunset", "exp_cmi_bookstore_work"],
                stats: .init(completionCount: 22, averageRating: 4.8),
                status: .active,
                createdAt: recent, updatedAt: recent
            ),
            Experience(
                id: "exp_cmi_khao_soi_1974",
                title: "Eat khao soi at the family stall open since 1974",
                oneLiner: "A 50-year-old khao soi stall where three generations still hand-fry the noodle nest.",
                whyItMatters: "Most khao soi tourists visit Khao Soi Khun Yai. Two streets away, a family has been running the same recipe since 1974. The crispy noodle nest is fried to order. There's a single round table where solo diners share with strangers. The mother takes orders; her grandson runs them out.",
                category: .food,
                location: ExperienceLocation(
                    coordinates: [98.9981, 18.7883], cityCode: "cmi",
                    addressHint: "Old City east gate area",
                    placeNameRomanized: "Khao Soi Mae 1974"
                ),
                bestTimes: [TimeWindow(startHour: 11, endHour: 14)],
                durationMinutes: .init(min: 20, max: 40),
                howTo: [
                    HowToStep(order: 1, text: "Arrive between 11:00 and 14:00 — they sell out."),
                    HowToStep(order: 2, text: "Order khao soi gai (chicken). One bowl, 60 baht."),
                    HowToStep(order: 3, text: "Add pickled mustard greens and shallots from the tray."),
                ],
                realInconveniences: [
                    RealInconvenience(category: .crowds, text: "Lunch rush 12:00–13:00. Come early or late."),
                    RealInconvenience(category: .logistics, text: "Cash only. Closed Sundays."),
                ],
                soloScore: SoloScore(
                    overall: 8.8,
                    breakdown: .init(seatingFriendly: 9, soloPatronRatio: 9, staffPressure: 9, soloPortioning: 10, ambianceFit: 8, safety: 9),
                    hint: "Round table is the solo seat. Just sit down.",
                    basedOnCount: 31
                ),
                sources: [
                    InformationSource(type: .blog, attribution: "EatingThaiFood", verifiedAt: recent),
                ],
                confidence: conf(level: 4, reason: "Trusted reporter visited last month"),
                nearbyExperienceIds: [],
                stats: .init(completionCount: 89, averageRating: 4.6),
                status: .active,
                createdAt: recent, updatedAt: recent
            ),
            Experience(
                id: "exp_cmi_doi_suthep_dawn",
                title: "Meditate with monks at Doi Suthep before the tourists arrive",
                oneLiner: "Morning chanting at 06:00, when the mountain temple is silent except for the bells.",
                whyItMatters: "Doi Suthep is a tour-bus circus by 09:00. At dawn, the gold chedi is yours. Monks chant in the main hall. You can sit at the back, no one expects anything. The cable car isn't running yet — you climb the 309 naga steps with the locals coming up to make merit.",
                category: .wellness,
                location: ExperienceLocation(
                    coordinates: [98.9216, 18.8048], cityCode: "cmi",
                    addressHint: "Doi Suthep mountain",
                    placeNameLocal: "วัดพระธาตุดอยสุเทพ",
                    placeNameRomanized: "Wat Phra That Doi Suthep"
                ),
                bestTimes: [TimeWindow(startHour: 5, endHour: 7, note: "Arrive before 06:00 chanting")],
                durationMinutes: .init(min: 60, max: 120),
                howTo: [
                    HowToStep(order: 1, text: "Take a red songthaew from the old city around 05:15."),
                    HowToStep(order: 2, text: "Climb the 309 naga steps — cable car not yet running."),
                    HowToStep(order: 3, text: "Sit at the back of the main viharn for 06:00 chanting."),
                    HowToStep(order: 4, text: "Walk the chedi clockwise three times before leaving."),
                ],
                realInconveniences: [
                    RealInconvenience(category: .logistics, text: "Songthaew at 05:15 may take 20+ min to fill. Negotiate a private fare if alone."),
                    RealInconvenience(category: .etiquette, text: "Cover shoulders and knees. Sit feet-tucked, never pointed at the Buddha."),
                    RealInconvenience(category: .weather, text: "Cold and damp before sunrise — bring a light layer."),
                ],
                soloScore: SoloScore(
                    overall: 8.5,
                    breakdown: .init(seatingFriendly: 9, soloPatronRatio: 7, staffPressure: 10, soloPortioning: 10, ambianceFit: 9, safety: 8),
                    hint: "Sit at the back. Stay still. No one will speak to you.",
                    basedOnCount: 11
                ),
                sources: [
                    InformationSource(type: .wikivoyage, attribution: "Wikivoyage", verifiedAt: recent),
                ],
                confidence: conf(level: 3, reason: "11 reports across last 30d, GPS-confirmed"),
                nearbyExperienceIds: [],
                stats: .init(completionCount: 28, averageRating: 4.9),
                status: .active,
                createdAt: recent, updatedAt: recent
            ),
            Experience(
                id: "exp_cmi_bookstore_work",
                title: "Work from the second floor of a bookstore nobody knows about",
                oneLiner: "A 100-year-old wooden shophouse with a quiet upstairs, free wifi, and a bottomless pot of jasmine tea.",
                whyItMatters: "Co-working spaces in Chiang Mai are crowded and loud. This bookstore — owned by a retired English professor — has a second floor with four desks, two armchairs, and a single rule: you must buy something. A pot of tea is 50 baht and lasts the afternoon. The wifi is fast. Nobody talks above a whisper.",
                category: .work,
                location: ExperienceLocation(
                    coordinates: [98.9939, 18.7869], cityCode: "cmi",
                    addressHint: "Old City near Tha Phae Gate",
                    placeNameRomanized: "Backstreet Books"
                ),
                bestTimes: [TimeWindow(startHour: 13, endHour: 18)],
                durationMinutes: .init(min: 120, max: 240),
                howTo: [
                    HowToStep(order: 1, text: "Enter the shop, nod to the owner, climb the wooden stairs."),
                    HowToStep(order: 2, text: "Pick a desk. Order a pot of jasmine tea downstairs (50 baht)."),
                    HowToStep(order: 3, text: "Stay as long as you like. Browse books on your way out."),
                ],
                realInconveniences: [
                    RealInconvenience(category: .logistics, text: "No power outlets at every desk. Charge before you arrive."),
                    RealInconvenience(category: .etiquette, text: "Whisper-quiet rule. No phone calls upstairs."),
                ],
                soloScore: SoloScore(
                    overall: 9.4,
                    breakdown: .init(seatingFriendly: 10, soloPatronRatio: 10, staffPressure: 10, soloPortioning: 10, ambianceFit: 9, safety: 9),
                    hint: "Built for solo. Whisper or stay silent.",
                    basedOnCount: 7
                ),
                sources: [
                    InformationSource(type: .user, attribution: "@solomdg", verifiedAt: recent),
                ],
                confidence: conf(level: 3, reason: "Newer find — 7 reports, 1 trusted"),
                nearbyExperienceIds: ["exp_cmi_khao_soi_1974"],
                stats: .init(completionCount: 12, averageRating: 4.9),
                status: .active,
                createdAt: recent, updatedAt: recent
            ),
        ]
    }()
}
