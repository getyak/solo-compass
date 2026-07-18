import SwiftData
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
    /// Called when the traveler taps "开始路线" — the host screen draws the route
    /// on the map and dismisses this detail. Defaults to a no-op so the other
    /// presentation sites (chat, requests, walked-routes) need no changes.
    var onStartRoute: (Route) -> Void

    @Environment(ExperienceService.self) private var service
    @Environment(UserPreferences.self) private var preferences
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var isSaved = false
    @State private var isFavorited = false
    @State private var heartBurstTrigger = 0
    @State private var showCompletionMoment = false
    @State private var showApprovalQueue = false
    // Single source of truth for the join / share sheets. Stacking two
    // `.sheet(isPresented:)` on one view collapses to only the last in SwiftUI
    // (the outer modifier overrides the inner), so a `.sheet(item:)` keyed on
    // this enum keeps both presentations working.
    @State private var activeSheet: RouteDetailSheet? = nil
    // Refreshes whenever RouteStore.didChange fires (join request submitted, accepted, etc.)
    @State private var liveRoute: Route

    public init(
        route: Route,
        onTapStop: @escaping (Experience) -> Void = { _ in },
        onStartRoute: @escaping (Route) -> Void = { _ in }
    ) {
        self.route = route
        self._liveRoute = State(initialValue: route)
        self.onTapStop = onTapStop
        self.onStartRoute = onStartRoute
    }

    // MARK: - Companion recruiting helpers

    private var viewerIsHost: Bool {
        guard let companion = liveRoute.companion else { return false }
        return companion.hostId == DeviceIdentityService.shared.deviceID
    }

    private var hasMyRequest: Bool {
        guard let companion = liveRoute.companion else { return false }
        let deviceId = DeviceIdentityService.shared.deviceID
        return companion.joinRequests.contains { $0.requesterId == deviceId && $0.status == .pending }
    }

    // MARK: - Primary category (majority category of stops)

    private var primaryCategory: ExperienceCategory {
        let stops = liveRoute.experienceIds.compactMap { service.getExperience(id: $0) }
        guard !stops.isEmpty else { return .hidden }
        var counts: [ExperienceCategory: Int] = [:]
        for stop in stops { counts[stop.category, default: 0] += 1 }
        return counts.max(by: { $0.value < $1.value })?.key ?? .hidden
    }

    // MARK: - Mono baseline string

    private var monoBaseline: String {
        let durStr = "\(liveRoute.estimatedDuration)"
        let distStr = "\(liveRoute.distanceMeters) m"
        let paceStr = liveRoute.pace.localizedLabel
        let bestStr = liveRoute.bestNow
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
        .sheet(item: $activeSheet) { sheet in
            switch sheet {
            case .join:
                JoinRouteRequestSheet(route: liveRoute)
            case .share:
                RouteShareSheet(payload: sharePayload)
            }
        }
        .fullScreenCover(isPresented: $showCompletionMoment) {
            CompletionMoment(route: liveRoute, onDismiss: { showCompletionMoment = false })
        }
        .navigationDestination(isPresented: $showApprovalQueue) {
            ApprovalQueueView(route: liveRoute, contextProvider: { modelContext })
        }
        .onReceive(NotificationCenter.default.publisher(for: RouteStore.didChange)) { note in
            // Accept both targeted (routeId key present) and broadcast (nil userInfo) changes.
            let affectedId = note.userInfo?["routeId"] as? String
            guard affectedId == nil || affectedId == route.id.rawValue else { return }
            if let updated = RouteStore(context: modelContext).get(route.id) {
                liveRoute = updated
            }
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

                Text(liveRoute.title)
                    .ctDisplay(26, .bold)
                    .foregroundStyle(.white)
                    .fixedSize(horizontal: false, vertical: true)

                if !liveRoute.summary.isEmpty {
                    Text(liveRoute.summary)
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
        Text(liveRoute.region)
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
            // Mono baseline — quiet JetBrains-Mono line with a bottom hairline
            // (border-subtle), per .sc-meta-row.
            metaRow

            // VerifiedBadge
            VerifiedBadge(route: liveRoute)
                .padding(.horizontal, 20)

            // RecruitingModule — only when companion feature is on and route has a companion slot
            if preferences.companionEnabled, let _ = liveRoute.companion {
                RecruitingModule(
                    route: liveRoute,
                    viewerIsHost: viewerIsHost,
                    hasMyRequest: hasMyRequest,
                    strength: preferences.companionModuleStrength,
                    onRequestJoin: {
                        activeSheet = .join
                    },
                    onViewRequests: {
                        showApprovalQueue = true
                    }
                )
                .padding(.horizontal, 16)
            }

            // StopsList
            StopsList(route: liveRoute, onTapStop: onTapStop)
                .background(CT.surfaceWhite)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(CT.borderSubtle, lineWidth: 0.5)
                )
                .padding(.horizontal, 16)

            // AI insight — locked Pro card (.sc-locked: dashed border, lock glyph, unlock CTA)
            aiInsightLocked
                .padding(.horizontal, 20)

            // Route tags (.sc-tag-row) — accent-soft pills, only when the route has tags
            if !liveRoute.tags.isEmpty {
                tagRow
                    .padding(.horizontal, 20)
            }
        }
    }

    // MARK: - Meta row (.sc-meta-row)

    private var metaRow: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(monoBaseline)
                .ctMono(12)
                .foregroundStyle(CT.fgMuted)
                .padding(.vertical, 14)
            Rectangle()
                .fill(CT.borderSubtle)
                .frame(height: 0.5)
        }
        .padding(.horizontal, 20)
        .padding(.top, 4)
    }

    // MARK: - AI insight locked card (.sc-locked)

    private var aiInsightLocked: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(NSLocalizedString("route.detail.aiInsight.title", comment: "AI insight section title"))
                .ctDisplay(12, .bold)
                .tracking(0.8)
                .textCase(.uppercase)
                .foregroundStyle(CT.fgMuted)

            HStack(spacing: 10) {
                ZStack {
                    Circle()
                        .fill(CT.surfaceWhite)
                        .frame(width: 28, height: 28)
                    Image(systemName: "lock.fill")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(CT.fgMuted)
                }
                Text(NSLocalizedString("route.detail.aiInsight.locked", comment: "AI insight unlock copy"))
                    .ctBody(12)
                    .foregroundStyle(CT.fgMuted)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 4)
                Text(NSLocalizedString("route.detail.aiInsight.unlock", comment: "Unlock CTA"))
                    .ctBody(12, .semibold)
                    .foregroundStyle(CT.accent)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(CT.surfaceSunken)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(
                        CT.borderDefault,
                        style: StrokeStyle(lineWidth: 0.5, dash: [4, 3])
                    )
            )
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: - Tag row (.sc-tag-row)

    private var tagRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(NSLocalizedString("route.detail.tags.title", comment: "Route tags section title"))
                .ctDisplay(12, .bold)
                .tracking(0.8)
                .textCase(.uppercase)
                .foregroundStyle(CT.fgMuted)

            FlowLayout(spacing: 6) {
                ForEach(liveRoute.tags, id: \.self) { tag in
                    Text(tag)
                        .ctBody(12)
                        .foregroundStyle(CT.accent)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(Capsule().fill(CT.accentSoft))
                        .overlay(Capsule().strokeBorder(CT.accentBorder, lineWidth: 1))
                }
            }
        }
    }

    // MARK: - Bottom dock

    private var showMarkCompleted: Bool {
        viewerIsHost && liveRoute.companion?.status == .closed
    }

    /// Resolved primary-CTA for the dock — label, SF symbol, disabled flag and
    /// action vary by companion state, mirroring route.jsx's dock logic:
    /// no-companion → 开始路线; viewer open/forming → 申请加入; host open/forming →
    /// 审批 N; hasMyRequest → 等待确认(disabled); closed/completed → 进入群聊.
    private struct PrimaryCTA {
        let label: String
        let systemImage: String
        let isDisabled: Bool
        let action: () -> Void
    }

    private var primaryCTA: PrimaryCTA {
        // Host of a closed route gets the "mark completed" celebration CTA.
        if showMarkCompleted {
            return PrimaryCTA(
                label: NSLocalizedString("completion.mark.done", comment: ""),
                systemImage: "checkmark.seal.fill",
                isDisabled: false,
                action: { showCompletionMoment = true }
            )
        }

        guard preferences.companionEnabled, let companion = liveRoute.companion else {
            return PrimaryCTA(
                label: NSLocalizedString("route.detail.start", comment: ""),
                systemImage: "location.north.line.fill",
                isDisabled: false,
                action: {
                    // Hand the route up to the map host (draws the polyline +
                    // numbered stops, frames the camera) and close this sheet.
                    onStartRoute(liveRoute)
                    dismiss()
                }
            )
        }

        let isRecruiting = companion.status == .open || companion.status == .forming

        if isRecruiting && viewerIsHost {
            let pending = companion.joinRequests.filter { $0.status == .pending }.count
            return PrimaryCTA(
                label: String(format: NSLocalizedString("route.detail.cta.review", comment: ""), pending),
                systemImage: "person.2.fill",
                isDisabled: false,
                action: { showApprovalQueue = true }
            )
        }
        if isRecruiting && hasMyRequest {
            return PrimaryCTA(
                label: NSLocalizedString("route.detail.cta.waiting", comment: ""),
                systemImage: "clock.fill",
                isDisabled: true,
                action: {}
            )
        }
        if isRecruiting {
            return PrimaryCTA(
                label: NSLocalizedString("route.detail.cta.requestJoin", comment: ""),
                systemImage: "person.2.fill",
                isDisabled: false,
                action: { activeSheet = .join }
            )
        }
        // closed / completed → group chat entry (falls back to completion replay
        // for a host on a completed route).
        return PrimaryCTA(
            label: NSLocalizedString("route.detail.cta.groupChat", comment: ""),
            systemImage: "message.fill",
            isDisabled: companion.status == .completed && !viewerIsHost,
            action: {
                if companion.status == .completed { showCompletionMoment = true }
            }
        )
    }

    private var bottomDock: some View {
        let cta = primaryCTA
        return VStack(spacing: 0) {
            Rectangle().fill(CT.borderSubtle).frame(height: 0.5)
            HStack(spacing: 12) {
                // Ghost button — favorite
                Button {
                    let willFavorite = !isFavorited
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                        isFavorited.toggle()
                    }
                    if willFavorite {
                        heartBurstTrigger += 1
                        Haptics.notify(.success)
                    } else {
                        Haptics.impact(.light)
                    }
                } label: {
                    Image(systemName: isFavorited ? "heart.fill" : "heart")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(isFavorited ? CT.toneClosed : CT.fgMuted)
                        .symbolEffect(.bounce, value: isFavorited)
                        .scaleEffect(isFavorited ? 1.12 : 1.0)
                        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isFavorited)
                        .frame(width: 44, height: 44)
                        .background(Circle().fill(CT.surfaceSunken))
                        .overlay { HeartBurstView(trigger: heartBurstTrigger) }
                }
                .accessibilityLabel(Text(NSLocalizedString("route.detail.favorite", comment: "")))
                .accessibilityValue(Text(isFavorited
                    ? NSLocalizedString("action.favorited", comment: "Favorited accessibility value")
                    : NSLocalizedString("action.notFavorited", comment: "Not favorited accessibility value")))

                // Ghost button — add to itinerary
                Button {
                    isSaved.toggle()
                } label: {
                    Image(systemName: isSaved ? "calendar.badge.checkmark" : "calendar.badge.plus")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(isSaved ? CT.accent : CT.fgMuted)
                        .frame(width: 44, height: 44)
                        .background(Circle().fill(CT.surfaceSunken))
                }
                .accessibilityLabel(Text(NSLocalizedString("route.detail.save", comment: "")))

                // Primary CTA — accent fill, state-dependent label.
                Button(action: cta.action) {
                    HStack(spacing: 6) {
                        Image(systemName: cta.systemImage)
                            .font(.system(size: 15, weight: .semibold))
                        Text(cta.label)
                            .ctBody(15, .semibold)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 44)
                    .foregroundStyle(cta.isDisabled ? CT.fgMuted : CT.surfaceWhite)
                    .background(
                        Capsule().fill(cta.isDisabled ? CT.surfaceSunken : CT.accent)
                    )
                }
                .disabled(cta.isDisabled)
                .accessibilityLabel(Text(cta.label))
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
            Button {
                activeSheet = .share
            } label: {
                Image(systemName: "square.and.arrow.up")
            }
            .accessibilityLabel(NSLocalizedString("route.share.title", comment: "Share route"))
        }
    }

    /// Pre-built payload for the share sheet — resolves the primary category,
    /// stop count, and ordered stop coordinates once so the sheet stays a pure
    /// visual layer. Coordinates drive the map-basemap / vector-trace share card.
    private var sharePayload: RouteSharePayload {
        let coordinates = liveRoute.experienceIds
            .compactMap { service.getExperience(id: $0) }
            .compactMap { $0.coordinate }
        return RouteSharePayload(
            route: liveRoute,
            category: primaryCategory,
            stopCount: liveRoute.experienceIds.count,
            coordinates: coordinates
        )
    }
}

// MARK: - RouteDetailSheet

/// Which modal RouteDetailView is presenting. A single `.sheet(item:)` keyed on
/// this enum avoids stacking two `.sheet(isPresented:)` modifiers (SwiftUI keeps
/// only the last, breaking the other).
enum RouteDetailSheet: Identifiable {
    case join
    case share

    var id: String {
        switch self {
        case .join:  return "join"
        case .share: return "share"
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

    let conf = Confidence(
        level: 4,
        lastVerifiedAt: recent,
        reason: "Preview",
        signals: .init(aiScrapeAgeDays: 7, passiveGpsHits30d: 24, activeReports30d: 8, trustedVerifications: 1)
    )

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
        confidence: conf,
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
        confidence: conf,
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
    .modelContainer(SoloCompassModelContainer.makeInMemory())
}
