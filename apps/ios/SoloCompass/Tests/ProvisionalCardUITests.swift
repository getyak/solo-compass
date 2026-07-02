import XCTest
import SwiftUI
import CoreLocation
@testable import SoloCompass

/// ⑩ Card 可反悔性 — slice B UI wiring tests.
///
/// These tests exercise the orchestrator → view surface added by slice B:
///
/// - `entriesByMessageId` stays in step with `cardsByMessageId`
/// - `advanceProvisionalClock()` advances the ledger without mutation
/// - `undoCard(id:)` targets a specific entry
/// - `ChatCardStack` + `UndoPill` render deterministically via `ImageRenderer`
///   (no simulator interaction needed — the whole point is to catch
///   regressions in the compact card+pill layout with a screenshot
///   dropped to /tmp).
@MainActor
final class ProvisionalCardUITests: XCTestCase {

    // MARK: - Fixtures

    private func makeIsolatedDefaults() -> UserDefaults {
        let suite = "provisional.uitest.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    private func makeExperience(id: String) -> Experience {
        let now = Date()
        return Experience(
            id: id,
            title: "Fixture \(id)",
            oneLiner: "Provisional UI fixture \(id)",
            whyItMatters: "Provisional UI fixture",
            category: .coffee,
            location: ExperienceLocation(coordinates: [114.05, 22.54], cityCode: "szx"),
            bestTimes: [],
            durationMinutes: .init(min: 30, max: 60),
            howTo: [],
            realInconveniences: [],
            soloScore: SoloScore(
                overall: 5,
                breakdown: .init(
                    seatingFriendly: 7, soloPatronRatio: 7, staffPressure: 7,
                    soloPortioning: 7, ambianceFit: 7, safety: 7
                ),
                basedOnCount: 1
            ),
            sources: [InformationSource(type: .user, attribution: "test", verifiedAt: now)],
            confidence: Confidence(
                level: 3,
                lastVerifiedAt: now,
                reason: "Test fixture",
                signals: .init(aiScrapeAgeDays: 1, passiveGpsHits30d: 0, activeReports30d: 0, trustedVerifications: 0)
            ),
            nearbyExperienceIds: [],
            stats: .init(completionCount: 0, averageRating: 0),
            status: .active,
            createdAt: now,
            updatedAt: now
        )
    }

    private final class Fixture {
        let orchestrator: VoiceAgentOrchestrator
        let vm: MapViewModel
        let prefs: UserPreferences
        init(orchestrator: VoiceAgentOrchestrator, vm: MapViewModel, prefs: UserPreferences) {
            self.orchestrator = orchestrator; self.vm = vm; self.prefs = prefs
        }
    }

    private func makeFixture() -> Fixture {
        let prefs = UserPreferences(defaults: makeIsolatedDefaults())
        prefs.lastSelectedCity = "szx"
        let vm = MapViewModel(
            locationService: LocationService(),
            experienceService: ExperienceService(seed: [makeExperience(id: "szx_1")]),
            aiService: AIService(),
            preferences: prefs
        )
        let orchestrator = VoiceAgentOrchestrator(
            aiService: AIService(),
            voiceService: VoiceService(),
            mapViewModel: vm,
            preferences: prefs
        )
        return Fixture(orchestrator: orchestrator, vm: vm, prefs: prefs)
    }

    private func exp(_ id: String) -> ChatCard {
        .experiences(id: UUID(), [makeExperience(id: id)])
    }

    // MARK: - entriesByMessageId parallel projection

    func testEntriesByMessageIdMirrorsCards() {
        let f = makeFixture()
        let msg = UUID()
        f.orchestrator.provisionalCards.append(card: exp("a"), to: msg, at: Date())
        f.orchestrator.advanceProvisionalClock()

        XCTAssertEqual(f.orchestrator.cardsByMessageId[msg]?.count, 1)
        XCTAssertEqual(f.orchestrator.entriesByMessageId[msg]?.count, 1,
                       "entries projection must be in lock-step with cards")
        if case .provisional = f.orchestrator.entriesByMessageId[msg]?.first?.state {
            // ok
        } else {
            XCTFail("first entry must land as .provisional")
        }
    }

    func testEntriesByMessageIdDropsUndone() {
        let f = makeFixture()
        let msg = UUID()
        f.orchestrator.provisionalCards.append(card: exp("a"), to: msg, at: Date())
        f.orchestrator.advanceProvisionalClock()

        let firstId = f.orchestrator.entriesByMessageId[msg]?.first?.id
        XCTAssertNotNil(firstId)
        _ = f.orchestrator.undoCard(id: firstId!)

        XCTAssertNil(f.orchestrator.entriesByMessageId[msg],
                     "undone entries must vanish from the entries projection")
        XCTAssertNil(f.orchestrator.cardsByMessageId[msg],
                     "undone entries must vanish from the cards projection too")
    }

    // MARK: - advanceProvisionalClock() is idempotent

    func testAdvanceProvisionalClockIsIdempotent() {
        let f = makeFixture()
        let msg = UUID()
        f.orchestrator.provisionalCards.append(card: exp("a"), to: msg, at: Date())
        f.orchestrator.advanceProvisionalClock()
        f.orchestrator.advanceProvisionalClock() // extra tick — must not crash
        f.orchestrator.advanceProvisionalClock()
        XCTAssertEqual(f.orchestrator.cardsByMessageId[msg]?.count, 1)
        XCTAssertEqual(f.orchestrator.entriesByMessageId[msg]?.count, 1)
    }

    // MARK: - nextProvisionalDeadline() forwarding

    func testNextProvisionalDeadlineForwardsLedger() {
        let f = makeFixture()
        let msg = UUID()
        XCTAssertNil(f.orchestrator.nextProvisionalDeadline())

        f.orchestrator.provisionalCards.append(card: exp("a"), to: msg, at: Date())
        XCTAssertNotNil(f.orchestrator.nextProvisionalDeadline(),
                        "with something provisional, deadline must be non-nil")
        f.orchestrator.commitAllProvisionalCards()
        XCTAssertNil(f.orchestrator.nextProvisionalDeadline(),
                     "after commit, nothing is scheduled")
    }

    // MARK: - ImageRenderer smoke test

    /// Renders a ChatCardStack with one provisional entry to a PNG under
    /// /tmp and asserts the file exists + is non-trivially sized. Doesn't
    /// pixel-match: that's brittle. Catches "compile broke", "layout
    /// crashed", "pill hid the card" via a manual look at the PNG.
    /// Same pattern as the existing `project_ios_visual_verify` memory.
    func testChatCardStackWithProvisionalRendersToPNG() throws {
        let exp1 = makeExperience(id: "img_1")
        let card = ChatCard.experiences(id: UUID(), [exp1])
        let entry = ProvisionalCardLedger.Entry(
            id: UUID(),
            messageId: UUID(),
            card: card,
            appearedAt: Date(),
            // Give it 3s so the pill has a meaningful countdown.
            state: .provisional(deadline: Date().addingTimeInterval(3))
        )
        let view = ChatCardStack(
            cards: [card],
            onSelectExperience: { _ in },
            onAdoptRoute: { _ in },
            entries: [entry],
            onUndoCard: { _ in }
        )
        .frame(width: 360)
        .background(Color(.systemBackground))
        .environment(\.locale, Locale(identifier: "en"))

        let renderer = ImageRenderer(content: view)
        renderer.scale = 2
        guard let uiImage = renderer.uiImage,
              let png = uiImage.pngData() else {
            return XCTFail("ImageRenderer produced no PNG data")
        }
        let outURL = URL(fileURLWithPath: "/tmp/undo_pill_stack.png")
        try png.write(to: outURL)
        let attrs = try FileManager.default.attributesOfItem(atPath: outURL.path)
        let size = (attrs[.size] as? NSNumber)?.intValue ?? 0
        XCTAssertGreaterThan(size, 2_000,
                             "PNG must be non-trivially sized (>2 KB); wrote \(size) bytes")
    }
}
