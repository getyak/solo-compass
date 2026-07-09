import SwiftUI
import SwiftData

/// Travel Archive tab (P1.1 #111).
///
/// Vertical bands:
/// 1. Trip summary card — current city, days, distinct Experience count.
/// 2. Timeline grouped by city, newest visit first.
/// 3. Capsule triage section (P2.4 #245).
/// 4. Rituals hub (P2/P3 goal-audit): a single row exposing every ritual
///    surface — Omen, Blindbox, CityCodex, Brag, OST, Insight, Capsule
///    open — so each shipped SwiftUI screen is reachable from the app,
///    not stranded behind a Preview.
/// 5. Year-end Travel Book banner (P3.4 #342, seasonal).
/// 6. Codex placeholder text.
public struct ArchiveView: View {

    @State private var viewModel: ArchiveViewModel
    @State private var ritualsSheet: RitualsSheet? = nil
    private let ritualsModelContainer: ModelContainer
    @Environment(\.colorScheme) private var colorScheme

    public init(modelContainer: ModelContainer, activeCityCode: String? = nil) {
        self.ritualsModelContainer = modelContainer
        _viewModel = State(initialValue: ArchiveViewModel(
            modelContainer: modelContainer,
            activeCityCode: activeCityCode
        ))
    }

    /// One case per ritual screen. `Identifiable` powers the sheet(item:)
    /// stack below so the map's UI stays clean when nothing is presented.
    enum RitualsSheet: String, Identifiable {
        case omen, blindbox, cityCodex, brag, ost, insight, capsuleOpen
        case liveActivity   // P2.2 audit preview (no real ActivityKit entitlement needed)
        case toolContract   // P2.1 / P3.5 audit preview (no chat UI needed)
        case bookManifest   // P3.4 audit preview (bypasses Nov/Dec gate)
        var id: String { rawValue }
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                if viewModel.isEmpty {
                    emptyState
                    // Rituals hub is available even in empty state so a
                    // fresh install can preview each ritual surface
                    // before any visit is recorded (goal-audit directive).
                    ritualsHub
                } else {
                    if let trip = viewModel.currentTrip {
                        tripCard(trip: trip)
                    }
                    ForEach(viewModel.groups) { group in
                        citySection(group: group)
                    }
                    // P2.4 #245: capsule triage — buried / ripe / opened.
                    // Reads directly from `CapsuleStore.shared` so the
                    // section reflects the same rows the LiveActivity
                    // trigger uses. Silent when empty (no zero-state).
                    capsuleSection

                    // P3.4 #342: year-end Travel Book teaser. Only in
                    // Nov/Dec so the banner is a genuine seasonal moment
                    // rather than a permanent upsell.
                    if Self.showsYearEndBanner(now: Date()) {
                        yearEndBookBanner
                    }

                    // Rituals hub — makes every P2/P3 ritual surface
                    // reachable so the goal audit (see the "都是有显示的"
                    // directive) can screenshot each one.
                    ritualsHub

                    codexPlaceholder
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 20)
        }
        .background(colorScheme == .dark ? Color(.systemBackground) : Color(white: 0.98))
        .navigationTitle(NSLocalizedString("archive.title", comment: "Travel archive title"))
        .onAppear {
            viewModel.refresh()
            #if DEBUG
            // Goal-audit entry point: `-ritualSheet <name>` pops the
            // corresponding ritual sheet on first appear so screenshots
            // can be captured without a tap on the grid tile.
            if let idx = ProcessInfo.processInfo.arguments.firstIndex(of: "-ritualSheet"),
               idx + 1 < ProcessInfo.processInfo.arguments.count,
               let sheet = RitualsSheet(rawValue: ProcessInfo.processInfo.arguments[idx + 1]) {
                ritualsSheet = sheet
            }
            #endif
        }
        .sheet(item: $ritualsSheet, content: ritualSheetContent(for:))
    }

    // MARK: - Rituals hub (P2/P3 goal-audit)

    @ViewBuilder
    private var ritualsHub: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Rituals")
                .font(.system(.headline, design: .rounded))
                .foregroundStyle((colorScheme == .dark ? CT.fgPrimaryDark : CT.fgPrimary).opacity(0.85))
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 108), spacing: 10)],
                spacing: 10
            ) {
                ritualTile("Today's Omen", "sparkles",       accent: CT.omenGold,      tap: .omen)
                ritualTile("Blindbox",     "shippingbox.fill", accent: CT.blindboxAmber, tap: .blindbox)
                ritualTile("City Codex",   "square.grid.3x3.fill", accent: CT.omenGold, tap: .cityCodex)
                ritualTile("Solo Brag",    "square.and.arrow.up.on.square.fill",
                           accent: CT.sunGoldDeep, tap: .brag)
                ritualTile("Today's OST",  "music.note",     accent: CT.accent,        tap: .ost)
                ritualTile("Monthly Insight", "chart.bar.doc.horizontal.fill",
                           accent: CT.sunGold, tap: .insight)
                ritualTile("Open a Capsule", "envelope.open.fill",
                           accent: CT.capsuleGlow, tap: .capsuleOpen)
                ritualTile("Live Activity",  "bell.badge.fill",
                           accent: CT.sunGoldDeep, tap: .liveActivity)
                ritualTile("Voice Tools",    "waveform.circle.fill",
                           accent: CT.accent, tap: .toolContract)
                ritualTile("Travel Book",    "book.pages.fill",
                           accent: CT.capsuleGlow, tap: .bookManifest)
            }
        }
        .accessibilityIdentifier("archive.ritualsHub")
    }

    @ViewBuilder
    private func ritualTile(_ label: String, _ symbol: String,
                            accent: Color, tap: RitualsSheet) -> some View {
        Button {
            ritualsSheet = tap
        } label: {
            VStack(spacing: 8) {
                Image(systemName: symbol)
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(accent)
                Text(label)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(colorScheme == .dark ? CT.fgPrimaryDark : CT.fgPrimary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, minHeight: 84)
            .padding(10)
            .background(colorScheme == .dark ? CT.warmCardDark : Color.white)
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(accent.opacity(0.28), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("archive.ritualsTile.\(tap.rawValue)")
    }

    @ViewBuilder
    private func ritualSheetContent(for sheet: RitualsSheet) -> some View {
        switch sheet {
        case .omen:
            NavigationStack {
                ScrollView {
                    OmenCardView(
                        data: OmenComposeService.shared.compose(
                            tasteDescriptors: viewModel.groups.map(\.cityCode)
                        ),
                        onMicroTaskDone: { ritualsSheet = nil }
                    )
                    .padding(.vertical, 24)
                }
                .navigationTitle("Today's Omen")
                .navigationBarTitleDisplayMode(.inline)
            }
        case .blindbox:
            BlindboxLaunchView(
                onLaunch: { _ in ritualsSheet = nil },
                onDismiss: { ritualsSheet = nil }
            )
        case .cityCodex:
            NavigationStack {
                CityCodexView(
                    entries: cityCodexEntries(),
                    isPro: false,
                    onUpsell: { ritualsSheet = nil }
                )
            }
        case .brag:
            NavigationStack {
                ScrollView {
                    BragCardView(
                        data: bragData(),
                        isVideoUnlocked: false,
                        onShare: { ritualsSheet = nil },
                        onWallpaper: { ritualsSheet = nil },
                        onVideoUnlock: { ritualsSheet = nil }
                    )
                    .padding(.vertical, 24)
                }
                .navigationTitle("Solo Brag")
                .navigationBarTitleDisplayMode(.inline)
            }
        case .ost:
            NavigationStack {
                ScrollView {
                    OstShareCard(
                        descriptor: ostDescriptor(),
                        onShare: { ritualsSheet = nil },
                        onRegenerate: { ritualsSheet = nil }
                    )
                    .padding(.vertical, 24)
                }
                .navigationTitle("Today's OST")
                .navigationBarTitleDisplayMode(.inline)
            }
        case .insight:
            NavigationStack {
                ScrollView {
                    InsightCardView(
                        data: insightData(),
                        onShare: { ritualsSheet = nil }
                    )
                    .padding(.vertical, 24)
                }
                .navigationTitle("Monthly Insight")
                .navigationBarTitleDisplayMode(.inline)
            }
        case .capsuleOpen:
            CapsuleOpenView(
                payload: capsuleOpenPreview(),
                onDismiss: { ritualsSheet = nil },
                onReply: { ritualsSheet = nil }
            )
        case .liveActivity:
            NavigationStack { LiveActivityAllKindsPreview() }
        case .toolContract:
            NavigationStack { ToolRouterContractPreview() }
        case .bookManifest:
            NavigationStack { travelBookManifestPreview }
        }
    }

    @ViewBuilder
    private var travelBookManifestPreview: some View {
        let (visits, exps) = loadRawVisitPair()
        let manifest = BookComposeService.shared.compose(
            forYear: Calendar.current.component(.year, from: Date()),
            visits: visits,
            experiences: exps
        )
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("Travel Book · manifest")
                    .font(.system(.headline, design: .rounded))
                    .foregroundStyle(CT.fgPrimary)
                Text("P3.4 #341/#342 — the shape of your year in print.")
                    .font(.caption)
                    .foregroundStyle(CT.fgMuted)

                VStack(alignment: .leading, spacing: 6) {
                    manifestRow("Year",         String(manifest.year))
                    manifestRow("Chapters",     "\(manifest.chapters.count) week-blocks")
                    manifestRow("Approx pages", "\(manifest.approxPageCount) pp")
                    manifestRow("Cover",        manifest.coverCaption)
                }
                .padding(14)
                .background(Color.white)
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(CT.borderSubtle, lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: 14))

                yearEndBookBanner
                    .accessibilityIdentifier("archive.bookBanner.forced")
            }
            .padding(20)
        }
        .background(colorScheme == .dark ? Color(.systemBackground) : Color(white: 0.98))
        .navigationTitle("Travel Book")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func manifestRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).font(.callout).foregroundStyle(CT.fgPrimary)
            Spacer()
            Text(value).font(.system(.callout, design: .monospaced))
                .foregroundStyle(CT.fgPrimary.opacity(0.72))
        }
    }

    // MARK: - Ritual data assembly (real fetch, deterministic fallback)

    /// Load the raw VisitRecord+ExperienceRecord pair. ArchiveViewModel
    /// already caches decorated rows but drops raw VisitRecord fields
    /// (coords, dwellSeconds arrays) that the composers need, so a
    /// dedicated read is cheaper than plumbing more through the VM.
    private func loadRawVisitPair() -> (visits: [VisitRecord], exps: [Experience]) {
        let ctx = ModelContext(ritualsModelContainer)
        let visits: [VisitRecord]
        do {
            var d = FetchDescriptor<VisitRecord>(
                sortBy: [SortDescriptor(\.visitedAt, order: .reverse)]
            )
            d.fetchLimit = 200
            visits = try ctx.fetch(d)
        } catch {
            visits = []
        }
        // Ritual composers need Experience objects but the visit set can
        // reference dozens of ids. #Predicate can't capture a `[String]`
        // in a Sendable KeyPath, so we fetch all records once and filter
        // in Swift. Archive is browsing-grade and the fetchLimit above
        // bounds this to 200 visits worst case.
        let ids = Set(visits.map(\.experienceId))
        let expRecs: [ExperienceRecord]
        if ids.isEmpty {
            expRecs = []
        } else {
            do {
                let all = try ctx.fetch(FetchDescriptor<ExperienceRecord>())
                expRecs = all.filter { ids.contains($0.id) }
            } catch {
                expRecs = []
            }
        }
        return (visits, expRecs.map { $0.asValue })
    }

    private func bragData() -> BragCardData {
        let (visits, exps) = loadRawVisitPair()
        let city = viewModel.currentTrip?.cityCode
            ?? viewModel.groups.first?.cityCode
            ?? "cmi"
        return BragCardComposer.shared.compose(
            cityCode: city,
            visits: visits,
            experiences: exps
        )
    }

    private func insightData() -> MonthlyInsightData {
        let (visits, exps) = loadRawVisitPair()
        return MonthlyInsightService.shared.compose(
            visits: visits,
            experiences: exps
        )
    }

    private func ostDescriptor() -> OstPlaylistDescriptor {
        let (visits, _) = loadRawVisitPair()
        return MusicService.shared.composeOst(for: visits, style: .jazz)
    }

    private func cityCodexEntries() -> [CityCodexView.Entry] {
        // Prefer the archive's known cities; if the user has never visited,
        // show today's omen as a lone tile so the grid renders something.
        let cities = viewModel.groups.map(\.cityCode)
        let today = OmenComposeService.shared.compose()
        return cities.prefix(6).enumerated().map { i, city in
            CityCodexView.Entry(
                id: Calendar.current.date(byAdding: .day, value: -i, to: today.date) ?? today.date,
                cityCode: city,
                line: today.line,
                completed: i == 0
            )
        } + (cities.isEmpty
             ? [CityCodexView.Entry(id: today.date, cityCode: "—",
                                    line: today.line, completed: false)]
             : [])
    }

    private func capsuleOpenPreview() -> CapsuleOpenView.PayloadRender {
        // Prefer a real ripe capsule; else show a deterministic placeholder
        // so the reveal animation is auditable end-to-end.
        if let ripe = CapsuleStore.shared.ripeCapsules().first,
           let text = String(data: ripe.contentBlob, encoding: .utf8), !text.isEmpty {
            return CapsuleOpenView.PayloadRender(
                title: "A note from you",
                bodyText: text,
                buriedAt: ripe.createdAt,
                contextLine: nil
            )
        }
        return CapsuleOpenView.PayloadRender(
            title: "A note from you",
            bodyText: "This is where your buried note will surface when it ripens.",
            buriedAt: Date().addingTimeInterval(-90 * 24 * 3600),
            contextLine: "Warm afternoon · cmi"
        )
    }

    // MARK: - P2.4 #245 capsule section

    @ViewBuilder
    private var capsuleSection: some View {
        let ripe = CapsuleStore.shared.ripeCapsules()
        let buried = CapsuleStore.shared.buriedUnripeCapsules()
        let opened = CapsuleStore.shared.openedCapsules()
        if ripe.isEmpty && buried.isEmpty && opened.isEmpty {
            EmptyView()
        } else {
            VStack(alignment: .leading, spacing: 10) {
                Text("Your capsules")
                    .font(.system(.subheadline, design: .rounded).weight(.semibold))
                    .foregroundStyle(CT.fgPrimary.opacity(0.85))
                capsuleRow(label: "Ripe to open", count: ripe.count, accent: CT.omenGold)
                capsuleRow(label: "Still buried", count: buried.count, accent: CT.sunGold)
                capsuleRow(label: "Already unwrapped", count: opened.count, accent: CT.fgMuted)
            }
        }
    }

    @ViewBuilder
    private func capsuleRow(label: String, count: Int, accent: Color) -> some View {
        HStack {
            Circle().fill(accent).frame(width: 6, height: 6)
            Text(label).font(.callout).foregroundStyle(CT.fgPrimary.opacity(0.85))
            Spacer()
            Text("\(count)").font(.callout.monospacedDigit()).foregroundStyle(CT.fgMuted)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(CT.borderSubtle, lineWidth: 1)
        )
    }

    // MARK: - P3.4 #342 year-end banner

    static func showsYearEndBanner(now: Date, calendar: Calendar = Calendar.current) -> Bool {
        #if DEBUG
        // Goal-audit entry point: `-forceYearEndBanner` overrides the
        // Nov/Dec gate so the P3.4 banner can be captured year-round.
        if ProcessInfo.processInfo.arguments.contains("-forceYearEndBanner") {
            return true
        }
        #endif
        let month = calendar.component(.month, from: now)
        return month >= 11
    }

    @ViewBuilder
    private var yearEndBookBanner: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Your year, in print.")
                .font(.system(.headline, design: .serif))
                .foregroundStyle(CT.fgPrimary)
            Text("Turn this year's archive into a printed book. Limited window.")
                .font(.footnote)
                .foregroundStyle(CT.fgMuted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(CT.capsuleGlow.opacity(0.55))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    // MARK: - Trip card

    @ViewBuilder
    private func tripCard(trip: ArchiveViewModel.TripSummary) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(trip.cityCode.uppercased())
                .font(.system(.title3, design: .rounded).weight(.semibold))
                .foregroundStyle(CT.fgPrimary)
            HStack(spacing: 16) {
                statChip(
                    value: "\(trip.dayCount)",
                    label: NSLocalizedString("archive.trip.days", comment: "Day count label")
                )
                statChip(
                    value: "\(trip.distinctExperienceCount)",
                    label: NSLocalizedString("archive.trip.places", comment: "Place count label")
                )
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(CT.accentSoft)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func statChip(value: String, label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.system(.title2, design: .rounded).weight(.bold))
                .foregroundStyle(CT.sunGold)
            Text(label)
                .font(.caption)
                .foregroundStyle(CT.fgPrimary.opacity(0.7))
        }
    }

    // MARK: - City section

    @ViewBuilder
    private func citySection(group: ArchiveViewModel.CityGroup) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(group.cityCode.uppercased())
                    .font(.system(.subheadline, design: .rounded).weight(.semibold))
                    .foregroundStyle(CT.fgPrimary.opacity(0.85))
                Spacer()
                Text(String(format: NSLocalizedString("archive.city.count", comment: "City visit count"), group.visits.count))
                    .font(.caption)
                    .foregroundStyle(CT.fgPrimary.opacity(0.5))
            }
            VStack(spacing: 8) {
                ForEach(group.visits) { visit in
                    visitRow(visit: visit)
                }
            }
        }
    }

    private func visitRow(visit: ArchiveViewModel.VisitedExperience) -> some View {
        HStack(alignment: .center, spacing: 12) {
            Circle()
                .fill(CT.sunGold)
                .frame(width: 8, height: 8)
            VStack(alignment: .leading, spacing: 2) {
                Text(visit.title)
                    .font(.system(.body, design: .rounded).weight(.medium))
                    .foregroundStyle(CT.fgPrimary)
                    .lineLimit(1)
                Text(formattedDate(visit.visitedAt))
                    .font(.caption)
                    .foregroundStyle(CT.fgPrimary.opacity(0.55))
            }
            Spacer()
            if visit.dwellSeconds >= 60 {
                Text("\(visit.dwellSeconds / 60)m")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(CT.fgPrimary.opacity(0.4))
            }
        }
        .padding(12)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(CT.borderSubtle, lineWidth: 1)
        )
    }

    private func formattedDate(_ date: Date) -> String {
        let fmt = DateFormatter()
        fmt.dateStyle = .medium
        fmt.timeStyle = .short
        return fmt.string(from: date)
    }

    // MARK: - Codex placeholder

    private var codexPlaceholder: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(NSLocalizedString("archive.codex.title", comment: "City codex title"))
                .font(.system(.headline, design: .rounded))
                .foregroundStyle(CT.fgPrimary.opacity(0.7))
            Text(NSLocalizedString("archive.codex.coming", comment: "City codex coming soon"))
                .font(.caption)
                .foregroundStyle(CT.fgPrimary.opacity(0.45))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(CT.borderSubtle, style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
        )
    }

    // MARK: - Empty state

    private var emptyState: some View {
        let fg = colorScheme == .dark ? CT.fgPrimaryDark : CT.fgPrimary
        return VStack(spacing: 16) {
            Image(systemName: "map.fill")
                .font(.system(size: 48, weight: .light))
                .foregroundStyle(CT.sunGold.opacity(0.45))
                .padding(.bottom, 4)
            Text(NSLocalizedString("archive.empty.title", comment: "Empty archive title"))
                .font(.system(.title3, design: .rounded).weight(.semibold))
                .foregroundStyle(fg.opacity(0.8))
            Text(NSLocalizedString("archive.empty.subtitle", comment: "Empty archive subtitle"))
                .font(.subheadline)
                .foregroundStyle(fg.opacity(0.5))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 56)
    }
}
