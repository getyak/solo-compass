import XCTest
import SwiftUI
import CoreLocation
@testable import SoloCompass

/// UI audit harness: renders the interaction-gated core surfaces (detail sheet,
/// settings, onboarding, paywall, UGC create form, chat cards, shared visual
/// components) to PNGs under `/tmp/sc-audit/xctest/` for human review. These are
/// screens `simctl` can't reach without driving navigation, so we render them
/// directly. No snapshot library ships — we assert only that a non-empty image
/// is produced; the PNGs themselves are eyeballed.
///
/// Two render strategies (per the established repo pattern):
///   • `render(_:)`  — ImageRenderer, lightweight self-sizing SwiftUI views.
///     Does NOT expand LazyVStack/ScrollView, so only for short/fixed content.
///   • `renderPage(_:)` — UIHostingController at a fixed 402×874 device frame,
///     for full pages wrapped in NavigationStack/ScrollView.
@MainActor
final class UIAuditSnapshotTests: XCTestCase {

    private static let outDir = URL(fileURLWithPath: "/tmp/sc-audit/xctest", isDirectory: true)

    // MARK: - Render helpers

    /// Lightweight ImageRenderer path for self-sizing components.
    private func render(_ view: some View, width: CGFloat = 393) -> UIImage? {
        let v = view
            .frame(width: width)
            .fixedSize(horizontal: false, vertical: true)
            .environment(\.colorScheme, .light)
        let r = ImageRenderer(content: v)
        r.scale = 2
        return r.uiImage
    }

    /// Full-page path: hosts the view at device size and draws the layer tree,
    /// so ScrollView/Lazy content expands. Pumps the run loop briefly so
    /// `onAppear`-driven content settles before the snapshot.
    private func renderPage(_ view: some View, settle: TimeInterval = 0.3) -> UIImage {
        let host = UIHostingController(rootView: view)
        host.overrideUserInterfaceStyle = .light
        host.view.frame = CGRect(x: 0, y: 0, width: 402, height: 874)

        let window = UIWindow(frame: host.view.frame)
        window.rootViewController = host
        window.makeKeyAndVisible()
        host.view.setNeedsLayout()
        host.view.layoutIfNeeded()
        if settle > 0 {
            RunLoop.main.run(until: Date().addingTimeInterval(settle))
        }
        host.view.setNeedsLayout()
        host.view.layoutIfNeeded()

        let renderer = UIGraphicsImageRenderer(bounds: host.view.bounds)
        return renderer.image { _ in
            host.view.drawHierarchy(in: host.view.bounds, afterScreenUpdates: true)
        }
    }

    private func write(_ image: UIImage?, _ name: String) throws {
        let img = try XCTUnwrap(image, "render produced no image for \(name)")
        XCTAssertGreaterThan(img.size.width, 0, "\(name): zero width")
        XCTAssertGreaterThan(img.size.height, 0, "\(name): zero height")
        try? FileManager.default.createDirectory(at: Self.outDir, withIntermediateDirectories: true)
        let data = try XCTUnwrap(img.pngData(), "\(name): pngData failed")
        try data.write(to: Self.outDir.appendingPathComponent("\(name).png"))
    }

    // MARK: - Shared environment chain

    /// The full service environment the map/detail/settings surfaces expect.
    /// Mirrors `SettingsSheetPresentationTests` so we don't trip SwiftUI's
    /// "no value for environment key" assertion.
    private func withServices(_ view: some View) -> some View {
        view
            .environment(LocationService())
            .environment(ExperienceService())
            .environment(AIService())
            .environment(UserPreferences())
            .environment(NotificationService.shared)
            .environment(SubscriptionService())
            .environment(CompanionService())
            .environment(PresenceService())
            .environment(BestNowClock.shared)
            .environment(LanguageService())
            .modelContainer(SoloCompassModelContainer.shared)
    }

    /// Prefer a Chiang Mai seed (richer card) when present, else first seed.
    private var primaryExperience: Experience {
        ExperienceService.hardcodedSeed.first(where: { $0.location.cityCode == "cmi" })
            ?? ExperienceService.hardcodedSeed.first!
    }

    // MARK: - 1. ExperienceDetailView (most important)

    func testExperienceDetailPage() throws {
        let exp = primaryExperience
        let vm = ExperienceDetailViewModel(
            experience: exp,
            experienceService: ExperienceService(),
            aiService: AIService(),
            preferences: UserPreferences()
        )
        let page = withServices(
            NavigationStack {
                ExperienceDetailView(viewModel: vm) {}
            }
        )
        try write(renderPage(page, settle: 0.6), "experience-detail")
    }

    // MARK: - 2. SettingsView

    func testSettingsPage() throws {
        let page = withServices(
            NavigationStack {
                SettingsView()
            }
        )
        try write(renderPage(page), "settings")
    }

    // MARK: - 3. FilterBarView (three selection states)
    //
    // The bar uses a horizontal ScrollView + a `.mask` driven by
    // `onPreferenceChange` width measurements. ImageRenderer doesn't run that
    // layout/preference plumbing, so the chips collapse to an empty capsule.
    // Host the bar in a real layout pass (over a tinted backdrop that stands in
    // for the map) and crop the snapshot to the bar's region.

    /// Renders `FilterBarView` on a backdrop at the top of a device-sized page,
    /// then crops to the top strip so the audit PNG is the bar only.
    private func renderFilterBar(_ bar: some View, _ name: String) throws {
        let page = ZStack(alignment: .top) {
            LinearGradient(
                colors: [Color(red: 0.62, green: 0.74, blue: 0.80), Color(red: 0.45, green: 0.60, blue: 0.55)],
                startPoint: .top, endPoint: .bottom
            )
            bar.padding(.top, 24)
        }
        let full = renderPage(page, settle: 0.4)
        // Crop the top ~120pt strip (×2 scale) to isolate the bar.
        let cropRect = CGRect(x: 0, y: 0, width: full.size.width * full.scale, height: 120 * full.scale)
        let cropped = full.cgImage.flatMap { $0.cropping(to: cropRect) }.map {
            UIImage(cgImage: $0, scale: full.scale, orientation: .up)
        }
        try write(cropped ?? full, name)
    }

    func testFilterBarCoffeeSelected() throws {
        let bar = FilterBarView(
            selectedCategory: .coffee,
            isNowSelected: false,
            nowCount: 3,
            onSelectNow: {},
            onSelectAll: {},
            onSelectCategory: { _ in }
        )
        .environment(UserPreferences())
        try renderFilterBar(bar, "filter-coffee")
    }

    func testFilterBarNowSelected() throws {
        let bar = FilterBarView(
            selectedCategory: nil,
            isNowSelected: true,
            nowCount: 3,
            onSelectNow: {},
            onSelectAll: {},
            onSelectCategory: { _ in }
        )
        .environment(UserPreferences())
        try renderFilterBar(bar, "filter-now")
    }

    func testFilterBarSavedSelected() throws {
        let bar = FilterBarView(
            selectedCategory: nil,
            isNowSelected: false,
            isFavoriteSelected: true,
            nowCount: 3,
            onSelectNow: {},
            onSelectAll: {},
            onSelectFavorite: {},
            onSelectCategory: { _ in }
        )
        .environment(UserPreferences())
        try renderFilterBar(bar, "filter-saved")
    }

    // MARK: - 4. OnboardingView

    func testOnboardingPage() throws {
        let page = OnboardingView(onComplete: {})
            .environment(LocationService.shared)
            .environment(UserPreferences())
            .environment(SubscriptionService())
        try write(renderPage(page), "onboarding")
    }

    // MARK: - 5. PaywallView

    func testPaywallPage() throws {
        let page = PaywallView()
            .environment(SubscriptionService())
        try write(renderPage(page), "paywall")
    }

    // MARK: - 6. Chat cards

    func testChatExperienceCard() throws {
        let exp = primaryExperience
        let card = ChatExperienceCard(experience: exp) {}
            .padding(12)
            .background(CT.bgWarm)
        try write(render(card), "chat-experience-card")
    }

    func testChatRouteProposalCard() throws {
        let stops = Array(ExperienceService.hardcodedSeed.prefix(3))
        guard stops.count >= 2 else { throw XCTSkip("need ≥2 seed places") }
        let route = Route(
            id: RouteId(rawValue: "audit-route"),
            title: "黄昏河畔漫步",
            summary: "从老城出发,沿河走到日落观景点。",
            experienceIds: stops.map(\.id),
            cityCode: stops.first?.location.cityCode ?? "VTE",
            region: "Riverfront",
            estimatedDuration: 75,
            distanceMeters: 1400,
            pace: .relaxed,
            tags: ["nature"],
            source: .aiGenerated,
            reasonNow: "日落将至 · 30 分钟后是最佳光线"
        )
        let proposal = RouteProposal(
            route: route,
            stops: stops,
            stopReasons: stops.enumerated().map { i, _ in "第 \(i + 1) 站 · 适合此刻停留" }
        )
        let card = ChatRouteProposalCard(proposal: proposal, onAdopt: {}, onTapStop: { _ in })
            .padding(12)
            .background(CT.bgWarm)
        try write(render(card), "chat-route-proposal")
    }

    func testChatReasoningTracePanel() throws {
        let steps = [
            ReasoningStep(kind: .thinking, label: "正在分析当下的时间与天气…"),
            ReasoningStep(kind: .tool, label: "🔍 搜索附近的安静咖啡馆…"),
            ReasoningStep(kind: .insight, label: "找到 3 个合适的地方"),
        ]
        let panel = ReasoningTracePanel(steps: steps)
            .padding(12)
            .background(CT.bgWarm)
        try write(render(panel), "chat-reasoning-trace")
    }

    // MARK: - 7. CreateExperienceSheet (UGC form)

    func testCreateExperienceSheet() throws {
        let sheet = CreateExperienceSheet(
            coordinate: CLLocationCoordinate2D(latitude: 18.7883, longitude: 98.9853),
            onSave: { _ in },
            onUseVoice: {},
            onCancel: {}
        )
        try write(renderPage(sheet), "create-experience")
    }

    // MARK: - 8. Shared visual components

    func testSoloScoreBadge() throws {
        let score = SoloScore(
            overall: 8.7,
            breakdown: .init(seatingFriendly: 9, soloPatronRatio: 8, staffPressure: 9, soloPortioning: 10, ambianceFit: 8, safety: 9),
            hint: "Order at the bar, sit upstairs.",
            basedOnCount: 14
        )
        let stack = VStack(spacing: 24) {
            SoloScoreBadge(score: score, style: .compact)
            SoloScoreBadge(score: score, style: .full)
        }
        .padding()
        .background(Color.white)
        try write(render(stack), "solo-score-badge")
    }

    func testConfidenceBadge() throws {
        let confidence = Confidence(
            level: 4,
            lastVerifiedAt: Date(),
            reason: "Verified by trusted reporter",
            signals: .init(aiScrapeAgeDays: 7, passiveGpsHits30d: 24, activeReports30d: 8, trustedVerifications: 1)
        )
        let stack = VStack(spacing: 16) {
            ConfidenceBadge(confidence: confidence, compact: false)
            ConfidenceBadge(confidence: confidence, compact: true)
        }
        .padding()
        .background(Color.white)
        try write(render(stack), "confidence-badge")
    }

    func testSoloScoreRadarChart() throws {
        let score = SoloScore(
            overall: 7.8,
            breakdown: .init(seatingFriendly: 9, soloPatronRatio: 3, staffPressure: 9, soloPortioning: 8, ambianceFit: 2, safety: 9),
            hint: "Great seating and safety, but noisy and few solo patrons.",
            basedOnCount: 22
        )
        let chart = SoloScoreRadarChart(score: score)
            .frame(width: 280, height: 280)
            .padding()
            .background(Color.white)
        try write(render(chart, width: 320), "solo-score-radar")
    }

    func testLocationCard() throws {
        let coord = CLLocationCoordinate2D(latitude: 18.7883, longitude: 98.9853)
        let locationService = LocationService()
        locationService.simulate(location: CLLocation(latitude: coord.latitude + 0.004, longitude: coord.longitude))
        let card = LocationCard(
            coordinate: coord,
            displayName: "Wat Phra Singh",
            addressHint: "2 Singharat Rd, Phra Sing, Chiang Mai"
        )
        .padding()
        .background(Color.white)
        .environment(locationService)
        try write(render(card), "location-card")
    }
}
