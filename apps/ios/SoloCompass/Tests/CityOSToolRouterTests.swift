import XCTest
@testable import SoloCompass

/// City OS v2 (PRD §5.2–5.3): end-to-end router tests for the two agent tools
/// `get_city_kit` / `find_local_events`. Mirrors `RecallMemoryToolTests` — pins
/// the wire envelope, the compliance-backed visa numbers, the effect emission,
/// the solo-score filter, and the dependency-unavailable surface.
@MainActor
final class CityOSToolRouterTests: XCTestCase {

    private func makeIsolatedDefaults() -> UserDefaults {
        let suite = "cityos.router.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    /// A seed payload (server row shape) so the injected `CityBriefService` has
    /// deterministic content without any network.
    private static let seedJSON = """
    {
      "kit": [
        {"city_code":"vte","section":"visa","name":"签证 / 税务","body":"落地签 30 天","lens_line":"计时离线可用","health":"green","last_verified_at":"2026-07-01T00:00:00Z","link_url":null,"link_label":null,"action":{"type":"visa_reminder","visa_days":30,"tax_line_days":183}},
        {"city_code":"vte","section":"safety","name":"安全","body":"市中心较稳","lens_line":"急救号码常驻","health":"green","last_verified_at":"2026-07-01T00:00:00Z","link_url":null,"link_label":null,"action":{"type":"emergency_numbers","numbers":[{"label":"警察","number":"191"}]}}
      ],
      "events": [
        {"id":"evt_vte_market","city_code":"vte","name":"夜市","category":"market","when_label":"本周每晚","starts_at":"2026-07-06T11:00:00Z","ends_at":"2999-01-01T00:00:00Z","solo_score":8.0,"solo_note":"独自逛无压力","health":"green","seen_label":"人工策展","lat":17.97,"lng":102.63,"limited_label":null,"source_url":"https://example.org"},
        {"id":"evt_vte_low","city_code":"vte","name":"喧闹派对","category":"music","when_label":"周六","starts_at":"2026-07-06T11:00:00Z","ends_at":"2999-01-01T00:00:00Z","solo_score":3.0,"solo_note":"人多","health":"green","seen_label":"人工策展","lat":17.98,"lng":102.64,"limited_label":null,"source_url":"https://example.org"},
        {"id":"evt_vte_notice","city_code":"vte","name":"步道封闭","category":"notice","when_label":"周三起","starts_at":"2026-07-06T11:00:00Z","ends_at":"2999-01-01T00:00:00Z","solo_score":null,"solo_note":"改走别处","health":"green","seen_label":"本地新闻","lat":17.96,"lng":102.60,"limited_label":"临时","source_url":"https://example.org"}
      ]
    }
    """

    /// Retains every collaborator: the router holds `cityBriefService` /
    /// `complianceService` weakly, so the fixture must keep strong refs or they
    /// deallocate the moment `makeFixture` returns and the tools see a nil
    /// dependency.
    private struct Fixture {
        let router: VoiceAgentToolRouter
        let vm: MapViewModel
        let prefs: UserPreferences
        let brief: CityBriefService
        let compliance: ComplianceService
    }

    private func makeFixture(withVisaEntry: Bool) -> Fixture {
        let prefs = UserPreferences(defaults: makeIsolatedDefaults())
        prefs.lastSelectedCity = "VTE"
        if withVisaEntry {
            prefs.visaEntryDate = Date().addingTimeInterval(-2 * 86_400) // 3 days stayed
            prefs.visaLengthDays = 30
        }
        let vm = MapViewModel(
            locationService: LocationService(),
            experienceService: ExperienceService(seed: []),
            aiService: AIService(),
            preferences: prefs
        )
        vm.selectCity("VTE")
        let compliance = ComplianceService(preferences: prefs)
        let seedData = Data(Self.seedJSON.utf8)
        let brief = CityBriefService(
            container: SoloCompassModelContainer.makeInMemory(),
            seedLoader: { _ in seedData }
        )
        let router = VoiceAgentToolRouter(
            mapViewModel: vm,
            preferences: prefs,
            aiService: nil,
            cityBriefService: brief,
            complianceService: compliance
        )
        return Fixture(router: router, vm: vm, prefs: prefs, brief: brief, compliance: compliance)
    }

    private func call(_ router: VoiceAgentToolRouter, _ name: String, _ args: String) async -> String {
        await router.execute(VoiceAgentSession.ToolCall(id: "1", name: name, argumentsJSON: args))
    }

    // MARK: - get_city_kit

    func testGetCityKitReturnsSectionsWithVisaNumbersFromCompliance() async throws {
        let fx = makeFixture(withVisaEntry: true)
        let json = await call(fx.router, "get_city_kit", "{}")
        let obj = try XCTUnwrap(parse(json))
        XCTAssertEqual(obj["ok"] as? Bool, true)
        XCTAssertEqual(obj["city_code"] as? String, "vte")
        let sections = try XCTUnwrap(obj["sections"] as? [[String: Any]])
        let visa = try XCTUnwrap(sections.first { ($0["section"] as? String) == "visa" })
        // 30-day visa, 3 days stayed → 27 remaining, 180 to the tax line.
        XCTAssertEqual(visa["visa_days_remaining"] as? Int, 27)
        XCTAssertEqual(visa["tax_days_remaining"] as? Int, 180)
        // Safety row surfaces the dialable numbers verbatim.
        let safety = try XCTUnwrap(sections.first { ($0["section"] as? String) == "safety" })
        let numbers = try XCTUnwrap(safety["emergency_numbers"] as? [[String: Any]])
        XCTAssertEqual(numbers.first?["number"] as? String, "191")
    }

    func testGetCityKitFlagsVisaSetupWhenNoEntryDate() async throws {
        let fx = makeFixture(withVisaEntry: false)
        let json = await call(fx.router, "get_city_kit", "{\"kinds\":[\"visa\"]}")
        let obj = try XCTUnwrap(parse(json))
        let sections = try XCTUnwrap(obj["sections"] as? [[String: Any]])
        let visa = try XCTUnwrap(sections.first)
        XCTAssertEqual(visa["visa_setup_needed"] as? Bool, true)
        XCTAssertNil(visa["visa_days_remaining"])
    }

    // MARK: - find_local_events

    func testFindLocalEventsSetsEventsEffectAndKeepsNotices() async throws {
        let fx = makeFixture(withVisaEntry: false)
        let json = await call(fx.router, "find_local_events", "{}")
        let obj = try XCTUnwrap(parse(json))
        XCTAssertEqual(obj["ok"] as? Bool, true)
        // All three (market 8.0, music 3.0, notice) pass with no floor.
        XCTAssertEqual(obj["count"] as? Int, 3)
        guard case let .events(list)? = fx.router.lastEffect else {
            return XCTFail("expected .events effect")
        }
        XCTAssertEqual(list.count, 3)
    }

    func testFindLocalEventsSoloScoreFloorFiltersButKeepsNotices() async throws {
        let fx = makeFixture(withVisaEntry: false)
        let json = await call(fx.router, "find_local_events", "{\"solo_score_min\":7}")
        let obj = try XCTUnwrap(parse(json))
        // market (8.0) passes, music (3.0) filtered, notice always kept → 2.
        XCTAssertEqual(obj["count"] as? Int, 2)
    }

    func testFindLocalEventsQueryMatchesNameAndNote() async throws {
        let fx = makeFixture(withVisaEntry: false)
        let json = await call(fx.router, "find_local_events", "{\"query\":\"夜市\"}")
        let obj = try XCTUnwrap(parse(json))
        XCTAssertEqual(obj["count"] as? Int, 1)
    }

    /// The keyword pass is soft: event content is local-language while the
    /// model's keyword is often English ("weekend"), so a miss must fall back
    /// to the window-filtered list (flagged `query_relaxed`) instead of a
    /// false "nothing on".
    func testFindLocalEventsUnmatchedQueryRelaxesInsteadOfStarving() async throws {
        let fx = makeFixture(withVisaEntry: false)
        let json = await call(fx.router, "find_local_events", "{\"query\":\"weekend\"}")
        let obj = try XCTUnwrap(parse(json))
        XCTAssertEqual(obj["count"] as? Int, 3)
        XCTAssertEqual(obj["query_relaxed"] as? Bool, true)
    }

    // MARK: - dependency unavailable

    func testMissingCityBriefServiceYieldsDependencyEnvelope() async throws {
        let prefs = UserPreferences(defaults: makeIsolatedDefaults())
        let vm = MapViewModel(
            locationService: LocationService(),
            experienceService: ExperienceService(seed: []),
            aiService: AIService(),
            preferences: prefs
        )
        vm.selectCity("VTE")
        // No cityBriefService injected.
        let router = VoiceAgentToolRouter(mapViewModel: vm, preferences: prefs, aiService: nil)
        let json = await call(router, "get_city_kit", "{}")
        // The structured fatal envelope carries the dependency reason.
        XCTAssertTrue(json.contains("dependency_unavailable") || json.contains("cityBriefService"),
                      "expected dependency-unavailable envelope, got: \(json)")
    }

    // MARK: - helpers

    private func parse(_ json: String) -> [String: Any]? {
        guard let data = json.data(using: .utf8) else { return nil }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }
}
