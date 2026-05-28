import SwiftUI

// MARK: - RouteDetailView

/// Pure-content route detail screen.
///
/// Layout (top → bottom):
///   1. Hero: gradient + category emoji + title + romanized + region badge
///   2. Mono baseline: duration · distance · pace · bestNow
///   3. VerifiedBadge
///   4. RecruitingModule (when companionEnabled && route.companion != nil)
///   5. StopsList (tapping a stop navigates to ExperienceDetailView)
///   6. Bottom dock: Save + Favorite CTAs
public struct RouteDetailView: View {
    let route: Route
    var onTapStop: (Experience) -> Void

    @Environment(ExperienceService.self) private var service
    @Environment(UserPreferences.self) private var preferences
    @State private var isSaved = false
    @State private var isFavorited = false
    @State private var showJoinSheet = false

    public init(route: Route, onTapStop: @escaping (Experience) -> Void = { _ in }) {
        self.route = route
        self.onTapStop = onTapStop
    }

    // MARK: - Companion recruiting helpers

    private var viewerIsHost: Bool {
        guard let companion = route.companion else { return false }
        return companion.hostId == DeviceIdentityService.shared.deviceID
    }

    private var hasMyRequest: Bool {
        guard let companion = route.companion else { return false }
        let deviceId = DeviceIdentityService.shared.deviceID
        return companion.joinRequests.contains { $0.requesterId == deviceId && $0.status == .pending }
    }

    // MARK: - Primary category (majority category of stops)

    private var primaryCategory: ExperienceCategory {
        let stops = route.experienceIds.compactMap { service.getExperience(id: $0) }
        guard !stops.isEmpty else { return .hidden }
        var counts: [ExperienceCategory: Int] = [:]
        for stop in stops { counts[stop.category, default: 0] += 1 }
        return counts.max(by: { $0.value < $1.value })?.key ?? .hidden
    }

    // MARK: - Mono baseline string

    private var monoBaseline: String {
        let durStr = "\(route.estimatedDuration)"
        let distStr = "\(route.distanceMeters) m"
        let paceStr = route.pace.localizedLabel
        let bestStr = route.bestNow
            ? NSLocalizedString("route.detail.bestNow.yes", comment: "")
            : NSLocalizedString("route.detail.bestNow.no", comment: "")
        return "\(durStr) min · \(distStr) · \(paceStr) · \(bestStr)"
    }

    // MARK: - Body

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                heroBlock
                contentStack
                Spacer(minLength: 100) // room for bottom dock
            }
        }
        .background(Color(.systemGroupedBackground))
        .safeAreaInset(edge: .bottom) { bottomDock }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { shareButton }
        .sheet(isPresented: $showJoinSheet) {
            JoinRouteRequestSheet(route: route)
        }
    }

    // MARK: - Hero

    private var heroBlock: some View {
        ZStack(alignment: .bottomLeading) {
            CategoryVisual.gradient(for: primaryCategory)
                .frame(maxWidth: .infinity)
                .frame(minHeight: 200)

            VStack(alignment: .leading, spacing: 6) {
                Text(CategoryVisual.emoji(for: primaryCategory))
                    .font(.system(size: 40))

                Text(route.title)
                    .font(.custom("SpaceGrotesk-Bold", size: 26).weight(.bold))
                    .foregroundStyle(.white)
                    .fixedSize(horizontal: false, vertical: true)

                if !route.summary.isEmpty {
                    Text(route.summary)
                        .font(.system(size: 13))
                        .foregroundStyle(.white.opacity(0.85))
                        .lineLimit(2)
                }

                HStack(spacing: 6) {
                    regionBadge
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 20)
            .padding(.top, 60)
        }
    }

    private var regionBadge: some View {
        Text(route.region)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(
                Capsule()
                    .fill(.white.opacity(0.25))
            )
    }

    // MARK: - Content stack

    private var contentStack: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Mono baseline
            Text(monoBaseline)
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 20)
                .padding(.top, 16)

            // VerifiedBadge
            VerifiedBadge(route: route)
                .padding(.horizontal, 20)

            // RecruitingModule — only when companion feature is on and route has a companion slot
            if preferences.companionEnabled, let _ = route.companion {
                RecruitingModule(
                    route: route,
                    viewerIsHost: viewerIsHost,
                    hasMyRequest: hasMyRequest,
                    strength: preferences.companionModuleStrength,
                    onRequestJoin: {
                        showJoinSheet = true
                    },
                    onViewRequests: {
                        // TODO: US-034 — push ApprovalQueueView
                    }
                )
                .padding(.horizontal, 16)
            }

            // StopsList
            StopsList(route: route, onTapStop: onTapStop)
                .background(Color(.secondarySystemGroupedBackground))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .padding(.horizontal, 16)
        }
    }

    // MARK: - Bottom dock

    private var bottomDock: some View {
        VStack(spacing: 0) {
            Divider()
            HStack(spacing: 12) {
                Button {
                    isSaved.toggle()
                } label: {
                    Label(
                        NSLocalizedString("route.detail.save", comment: ""),
                        systemImage: isSaved ? "bookmark.fill" : "bookmark"
                    )
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .tint(isSaved ? .accentColor : .secondary)

                Button {
                    isFavorited.toggle()
                } label: {
                    Label(
                        NSLocalizedString("route.detail.favorite", comment: ""),
                        systemImage: isFavorited ? "heart.fill" : "heart"
                    )
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(isFavorited ? .pink : .accentColor)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .background(.bar)
        }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var shareButton: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            ShareLink(item: route.title) {
                Image(systemName: "square.and.arrow.up")
            }
        }
    }
}

// MARK: - Pace localization

extension Pace {
    var localizedLabel: String {
        switch self {
        case .relaxed:  return NSLocalizedString("route.detail.pace.relaxed", comment: "")
        case .standard: return NSLocalizedString("route.detail.pace.standard", comment: "")
        case .packed:   return NSLocalizedString("route.detail.pace.packed", comment: "")
        }
    }
}

// MARK: - Preview

#Preview("mekong-sunset route") {
    let now = Date()
    let recent = Calendar.current.date(byAdding: .day, value: -7, to: now) ?? now

    func conf() -> Confidence {
        Confidence(
            level: 4,
            lastVerifiedAt: recent,
            reason: "Preview",
            signals: .init(aiScrapeAgeDays: 7, passiveGpsHits30d: 24, activeReports30d: 8, trustedVerifications: 1)
        )
    }

    let mekongExp = Experience(
        id: "exp_vte_mekong_riverside_sunset",
        title: "Watch the sun fall into Thailand from the Mekong promenade",
        oneLiner: "Plastic chairs, cheap Beerlao, and a river that swallows the sun in 12 minutes.",
        whyItMatters: "The Mekong here is the border.",
        category: .nature,
        location: ExperienceLocation(
            coordinates: [102.6093, 17.9633],
            cityCode: "VTE",
            addressHint: "Chao Anouvong Park, Quai Fa Ngum",
            placeNameLocal: "ແມ່ນ້ຳຂອງ",
            placeNameRomanized: "Mae Nam Khong"
        ),
        bestTimes: [TimeWindow(startHour: 17, endHour: 19)],
        durationMinutes: .init(min: 45, max: 90),
        howTo: [],
        realInconveniences: [],
        soloScore: SoloScore(
            overall: 9.0,
            breakdown: .init(seatingFriendly: 10, soloPatronRatio: 7, staffPressure: 10, soloPortioning: 9, ambianceFit: 9, safety: 9),
            basedOnCount: 22
        ),
        sources: [],
        confidence: conf(),
        nearbyExperienceIds: [],
        stats: .init(completionCount: 22, averageRating: 4.8),
        status: .active,
        createdAt: recent,
        updatedAt: recent
    )

    let watExp = Experience(
        id: "exp_vte_wat_si_saket_morning",
        title: "Sit alone in the oldest surviving temple in Vientiane at dawn",
        oneLiner: "Clay Buddha niches, terracotta floor, and 6,840 ceramic figurines — all to yourself before 8am.",
        whyItMatters: "Wat Si Saket was built in 1818.",
        category: .culture,
        location: ExperienceLocation(
            coordinates: [102.6161, 17.9629],
            cityCode: "VTE",
            addressHint: "Lane Xang Ave, Vientiane",
            placeNameLocal: "ວັດສີສະເກດ",
            placeNameRomanized: "Wat Si Saket"
        ),
        bestTimes: [TimeWindow(startHour: 8, endHour: 10)],
        durationMinutes: .init(min: 30, max: 60),
        howTo: [],
        realInconveniences: [],
        soloScore: SoloScore(
            overall: 8.8,
            breakdown: .init(seatingFriendly: 9, soloPatronRatio: 6, staffPressure: 10, soloPortioning: 10, ambianceFit: 10, safety: 8),
            basedOnCount: 18
        ),
        sources: [],
        confidence: conf(),
        nearbyExperienceIds: [],
        stats: .init(completionCount: 30, averageRating: 4.9),
        status: .active,
        createdAt: recent,
        updatedAt: recent
    )

    let route = Route(
        id: RouteId(rawValue: "mekong-sunset"),
        title: "Mekong Sunset Walk",
        summary: "A 45-minute promenade walk that ends on a plastic chair facing Thailand.",
        experienceIds: ["exp_vte_mekong_riverside_sunset", "exp_vte_wat_si_saket_morning"],
        cityCode: "VTE",
        region: "Riverfront",
        estimatedDuration: 90,
        distanceMeters: 1200,
        pace: .relaxed,
        source: .editorial,
        bestNow: true,
        verification: RouteVerification(status: .walkedBy, walkedByCount: 12, walkedBy: ["maya", "leo"])
    )

    let service = ExperienceService(seed: [mekongExp, watExp])

    NavigationStack {
        RouteDetailView(route: route, onTapStop: { _ in })
            .environment(service)
            .environment(UserPreferences())
    }
}
