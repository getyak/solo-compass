import SwiftUI
import CoreLocation

/// Floating card that slides up when a marker is tapped. Tap → expand. Swipe
/// down → dismiss. Swipe up → full detail sheet.
public struct ExperienceCardView: View {
    let experience: Experience
    var onExpand: () -> Void
    var onDismiss: () -> Void
    /// Optional: tap handler for the "Deep cross-compile" menu item (Approach
    /// A). Nil hides the menu entirely (previews / contexts without a map VM).
    var onRecompile: (() -> Void)?
    /// True while THIS card is mid-recompile — swaps the menu for a spinner.
    var isRecompiling: Bool = false

    private struct DragState {
        var translation: CGFloat = 0
        var hapticFired: Bool = false
    }

    @GestureState private var dragState = DragState()
    @State private var dragOffset: CGFloat = 0
    @State private var heartBounce = 0
    @State private var heartBurst = false
    @State private var arrivedPulse = false
    @State private var didFireArrival = false
    @State private var arrivalGlow = false
    @State private var didFireOnCourse = false
    @State private var onCourseSnap = false
    @State private var lastProximityBand: ProximityTint?
    @State private var proximityPop = false
    @State private var bestTimeAppeared = false
    @State private var clockNudge = false

    private static let arrivedThresholdMeters = 75.0

    @Environment(UserPreferences.self) private var preferences
    @Environment(LocationService.self) private var locationService
    @Environment(AIService.self) private var aiService
    @Environment(BestNowClock.self) private var clock
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// True when the most recent synthesis degraded to skeleton placeholders.
    /// Drives the transparency pill so users don't mistake generic OSM fallback
    /// copy for a real AI-authored recommendation (US-004).
    private var isSkeletonData: Bool {
        aiService.lastSynthesisQuality == .skeleton
    }


    private var isArrived: Bool {
        (distanceMeters ?? .greatestFiniteMagnitude) <= Self.arrivedThresholdMeters
    }

    /// Finite distance in meters, or nil when location is unknown.
    private var distanceMeters: Double? {
        guard let coord = experience.coordinate else { return nil }
        let d = locationService.distance(to: coord)
        // greatestFiniteMagnitude is the sentinel returned when no fix is available;
        // isFinite alone cannot distinguish it from a real reading.
        return (d.isFinite && d < .greatestFiniteMagnitude) ? d : nil
    }

    /// Heading-corrected bearing: 0 = straight ahead. Falls back to absolute bearing
    /// when the device has no compass or heading accuracy is invalid.
    private var relativeBearingDegrees: Double? {
        guard let coord = experience.coordinate else { return nil }
        return locationService.relativeBearing(to: coord)
    }

    /// True when the experience is within ±15° of the user's current heading.
    private var isOnCourse: Bool {
        guard let bearing = relativeBearingDegrees else { return false }
        // Normalize to -180...180 so ±179° readings don't falsely trigger.
        let normalized = bearing.truncatingRemainder(dividingBy: 360)
        let clamped = normalized > 180 ? normalized - 360 : normalized < -180 ? normalized + 360 : normalized
        return abs(clamped) <= 15
    }

    /// Maps a bearing in degrees to a localized compass direction string (8 sectors).
    private static func compassDirection(for degrees: Double) -> String {
        let directions = [
            NSLocalizedString("compass.N", comment: "North"),
            NSLocalizedString("compass.NE", comment: "Northeast"),
            NSLocalizedString("compass.E", comment: "East"),
            NSLocalizedString("compass.SE", comment: "Southeast"),
            NSLocalizedString("compass.S", comment: "South"),
            NSLocalizedString("compass.SW", comment: "Southwest"),
            NSLocalizedString("compass.W", comment: "West"),
            NSLocalizedString("compass.NW", comment: "Northwest"),
        ]
        let raw = Int((degrees / 45.0).rounded())
        let index = ((raw % 8) + 8) % 8
        return directions[index]
    }

    private enum ProximityTint: Comparable {
        case far, mid, near

        private var rank: Int {
            switch self {
            case .far: return 0
            case .mid: return 1
            case .near: return 2
            }
        }

        static func < (lhs: ProximityTint, rhs: ProximityTint) -> Bool {
            lhs.rank < rhs.rank
        }

        static func from(meters: Double) -> ProximityTint {
            if meters <= 300 { return .near }
            if meters <= 1000 { return .mid }
            return .far
        }

        var color: Color {
            switch self {
            case .near: return .green
            case .mid: return Color(red: 0xF5/255, green: 0x9E/255, blue: 0x0B/255)
            case .far: return Color.secondary
            }
        }
    }

    private func proximityTint(for meters: Double) -> Color {
        ProximityTint.from(meters: meters).color
    }

    private static let distanceFormatter: MeasurementFormatter = {
        let f = MeasurementFormatter()
        f.unitOptions = .naturalScale
        f.unitStyle = .short
        f.numberFormatter.maximumFractionDigits = 1
        return f
    }()

    private static let walkThresholdMeters = 1500.0
    private static let walkMetersPerMin = 80.0

    private static let etaFormatter: DateFormatter = {
        let f = DateFormatter()
        f.timeStyle = .short
        f.dateStyle = .none
        return f
    }()

    /// Returns a (text, SF Symbol name) pair for the distance pill.
    /// Under 1 500 m → walk-minutes + figure.walk; otherwise → formatted distance + location.fill.
    private static func formatDistance(_ meters: Double) -> (text: String, symbol: String) {
        if meters < walkThresholdMeters {
            let minutes = Int((meters / walkMetersPerMin).rounded(.up))
            let label: String
            if minutes < 1 {
                label = NSLocalizedString("card.distance.walkSub1", comment: "Distance less than 1 min walk")
            } else {
                label = String(format: NSLocalizedString("card.distance.walk", comment: "Distance in walk minutes"), minutes)
            }
            return (label, "figure.walk")
        }
        let measurement = Measurement(value: meters, unit: UnitLength.meters)
        return (distanceFormatter.string(from: measurement), "location.fill")
    }

    public init(
        experience: Experience,
        onExpand: @escaping () -> Void,
        onDismiss: @escaping () -> Void,
        onRecompile: (() -> Void)? = nil,
        isRecompiling: Bool = false
    ) {
        self.experience = experience
        self.onExpand = onExpand
        self.onDismiss = onDismiss
        self.onRecompile = onRecompile
        self.isRecompiling = isRecompiling
    }

    /// Rubber-bands upward drags to 40% travel; downward dismissal drags follow 1:1.
    private func rubberBanded(_ t: CGFloat) -> CGFloat {
        t < 0 ? t * 0.4 : t
    }

    private var totalOffset: CGFloat {
        rubberBanded(dragState.translation) + dragOffset
    }

    /// Fades in both directions: downward (dismiss) and upward (expand).
    private var dragOpacity: Double {
        1 - min(0.4, abs(dragState.translation) / 300)
    }

    private var isFavorited: Bool {
        preferences.favoritedExperiences.contains(experience.id)
    }

    private var availableNavigationApps: [NavigationApp] {
        NavigationLauncher.availableApps()
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: experience.category.symbol)
                    .foregroundStyle(.white)
                    .frame(width: 32, height: 32)
                    .background(Circle().fill(experience.category.color))

                VStack(alignment: .leading, spacing: 2) {
                    Text(experience.title)
                        .font(.headline)
                        .lineLimit(2)
                    Text(experience.location.placeNameRomanized ?? experience.location.addressHint ?? "")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer()
                Button {
                    let wasFavorited = preferences.isFavorited(experience.id)
                    Haptics.impact(.light)
                    withAnimation(.spring(response: 0.3)) {
                        preferences.toggleFavorite(experience.id)
                    }
                    if !wasFavorited {
                        heartBounce += 1
                        if !reduceMotion {
                            heartBurst = true
                            Task {
                                try? await Task.sleep(nanoseconds: 450_000_000)
                                heartBurst = false
                            }
                        }
                    }
                } label: {
                    let favorited = preferences.isFavorited(experience.id)
                    ZStack {
                        Circle()
                            .stroke(Color.red.opacity(0.5), lineWidth: 2)
                            .scaleEffect(heartBurst ? 1.8 : 0.4)
                            .opacity(heartBurst ? 0 : 0.8)
                            .animation(.easeOut(duration: 0.45), value: heartBurst)
                            .allowsHitTesting(false)
                        Image(systemName: favorited ? "heart.fill" : "heart")
                            .foregroundStyle(favorited ? Color.red : Color.secondary)
                            .scaleEffect(favorited ? 1.15 : 1.0)
                            .symbolEffect(.bounce, value: heartBounce)
                    }
                    // US-019: keep the visible heart 32×32 but expand the
                    // tappable region to the 44pt HIG minimum.
                    .frame(width: 32, height: 32)
                    .frame(
                        minWidth: HitTargetMetrics.minimum,
                        minHeight: HitTargetMetrics.minimum
                    )
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(preferences.isFavorited(experience.id)
                    ? NSLocalizedString("card.favorite.remove", comment: "Remove from favorites")
                    : NSLocalizedString("card.favorite.add", comment: "Add to favorites"))
                ConfidenceBadge(confidence: experience.confidence, compact: true)
                recompileMenu
            }

            Text(experience.oneLiner)
                .font(.subheadline)
                .foregroundStyle(.primary)
                .lineLimit(3)

            // US-004: transparency pill — only for degraded skeleton data,
            // never for real or cached AI synthesis.
            if isSkeletonData {
                SkeletonBadgeView()
            }

            FlowLayout(spacing: 8) {
                SoloScoreBadge(score: experience.soloScore, style: .compact)
                Group {
                    if isArrived {
                        arrivedPill
                    } else if let meters = distanceMeters {
                        let dl = Self.formatDistance(meters)
                        distancePill(dl.text, symbol: dl.symbol)
                    }
                }
                .contentTransition(.numericText())
                .animation(.spring(response: 0.4), value: distanceMeters)
                if let meters = distanceMeters, !isArrived, meters < Self.walkThresholdMeters {
                    etaPill(meters: meters)
                }
                if !experience.realInconveniences.isEmpty {
                    inconveniencePill
                } else if experience.isBestNow() {
                    BestNowBadge(experience: experience)
                } else if let hint = experience.bestTimeHint() {
                    bestTimeHintPill(hint)
                }
                if let coord = experience.coordinate {
                    directionsControl(coordinate: coord)
                }
                Button(action: onExpand) {
                    Text(NSLocalizedString("experience.viewDetails", comment: "View details"))
                        .font(.subheadline.weight(.medium))
                }
            }
        }
        .padding(16)
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: 20)
                    .stroke(Color.green.opacity(arrivalGlow ? 0 : 0.7), lineWidth: 3)
                    .scaleEffect(arrivalGlow ? 1.25 : 1.0)
                    .animation(.easeOut(duration: 0.8), value: arrivalGlow)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
                RoundedRectangle(cornerRadius: 20)
                    .fill(.regularMaterial)
                    // Card now floats ABOVE the BottomInfoSheet, so it casts a
                    // soft downward shadow onto the sheet to read as "lifted",
                    // instead of the former upward (y:-2) shadow that suited a
                    // card pinned to the screen bottom.
                    .shadow(color: .black.opacity(0.16), radius: 16, y: 6)
            }
        )
        .offset(y: totalOffset)
        .opacity(dragOpacity)
        .padding(.horizontal, 12)
        .offset(y: dragOffset)
        .opacity(dragOpacity)
        .gesture(
            DragGesture(minimumDistance: 10)
                .updating($dragState) { value, state, _ in
                    let t = value.translation.height
                    state.translation = t
                    if abs(t) > 60 && !state.hapticFired {
                        Haptics.impact(.medium)
                        state.hapticFired = true
                    }
                }
                .onEnded { value in
                    // Capture live offset before @GestureState resets to 0.
                    let snappingFrom = rubberBanded(dragState.translation)
                    if value.translation.height > 60 {
                        dragOffset = 0
                        onDismiss()
                    } else if value.translation.height < -60 {
                        dragOffset = 0
                        onExpand()
                    } else {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                            dragOffset = 0
                        }
                    }
                }
        )
        .onTapGesture { onExpand() }
        .onChange(of: isArrived) { _, arrived in
            guard arrived, !didFireArrival else { return }
            didFireArrival = true
            Haptics.notify(.success)
            if !reduceMotion {
                arrivalGlow = true
                Task {
                    try? await Task.sleep(nanoseconds: 800_000_000)
                    arrivalGlow = false
                }
            }
        }
        .onAppear {
            Haptics.impact(.light)
        }
        .transition(.move(edge: .bottom).combined(with: .opacity))
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text(
            "\(experience.title). \(experience.oneLiner). " +
            String(format: NSLocalizedString("solo.a11y", comment: "Solo Score %@ of 10"),
                   String(format: "%.1f", experience.soloScore.overall)) +
            {
                var parts = ""
                if isArrived {
                    parts += ". " + NSLocalizedString("card.distance.arrived.a11y", comment: "You're here accessibility label")
                } else if let meters = distanceMeters {
                    parts += ". " + Self.formatDistance(meters).text
                }
                let count = experience.realInconveniences.count
                if count > 0 {
                    parts += ". " + String(format: NSLocalizedString("inconvenience.card.a11y", comment: "Heads up: N things to know"), count)
                } else if let hint = experience.bestTimeHint() {
                    parts += ". " + String(format: NSLocalizedString("experience.bestTime.hint.a11y", comment: "Best time accessibility"), hint)
                }
                if experience.coordinate != nil && !availableNavigationApps.isEmpty {
                    parts += ". " + NSLocalizedString("action.directions", comment: "Directions accessibility action")
                }
                return parts
            }()
        ))
        .accessibilityHint(Text(NSLocalizedString("experience.card.hint", comment: "Double tap to view details")))
        .accessibilityAction(
            named: Text(isFavorited
                ? NSLocalizedString("action.unfavorite", comment: "Remove favorite")
                : NSLocalizedString("action.favorite", comment: "Add favorite"))
        ) {
            preferences.toggleFavorite(experience.id)
        }
        .accessibilityAction(named: Text(NSLocalizedString("action.directions", comment: "Directions accessibility action"))) {
            guard let coord = experience.coordinate,
                  let app = availableNavigationApps.first else { return }
            NavigationLauncher.open(app: app, coordinate: coord, name: experience.title)
        }
    }

    @ViewBuilder
    private func distancePill(_ label: String, symbol: String) -> some View {
        let relBearing = relativeBearingDegrees
        let proximityColor = distanceMeters.map { proximityTint(for: $0) } ?? Color.secondary
        let arrowTint = isOnCourse ? Color.green : proximityColor
        HStack(spacing: 4) {
            if let relBearing {
                Image(systemName: "location.north.fill")
                    .font(.caption2)
                    .foregroundStyle(arrowTint)
                    .rotationEffect(.degrees(relBearing))
                    .scaleEffect(onCourseSnap ? 1.25 : 1.0)
                    .animation(
                        reduceMotion ? nil : .easeInOut(duration: 0.25),
                        value: relBearing
                    )
                    .animation(
                        reduceMotion ? nil : .easeInOut(duration: 0.3),
                        value: distanceMeters
                    )
                    .animation(
                        reduceMotion ? nil : .spring(response: 0.25, dampingFraction: 0.5),
                        value: onCourseSnap
                    )
                    .accessibilityHidden(true)
            }
            Label(label, systemImage: symbol)
                .font(.caption)
                .foregroundStyle(Color.secondary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Capsule().fill(Color.secondary.opacity(0.12)))
        .scaleEffect(proximityPop && !reduceMotion ? 1.18 : 1.0)
        .animation(.spring(response: 0.25, dampingFraction: 0.5), value: proximityPop)
        .onChange(of: distanceMeters) { _, meters in
            guard let meters else { return }
            let current = ProximityTint.from(meters: meters)
            defer { lastProximityBand = current }
            guard let last = lastProximityBand, current > last else { return }
            let style: UIImpactFeedbackGenerator.FeedbackStyle = current == .near ? .medium : .light
            Haptics.impact(style)
            if current == .near {
                UIAccessibility.post(
                    notification: .announcement,
                    argument: NSLocalizedString("card.proximity.closer", comment: "VoiceOver announcement when user enters the near proximity band")
                )
            }
            if !reduceMotion {
                proximityPop = true
                Task {
                    try? await Task.sleep(nanoseconds: 300_000_000)
                    proximityPop = false
                }
            }
        }
        .onChange(of: isOnCourse) { _, onCourse in
            if onCourse {
                guard !didFireOnCourse else { return }
                didFireOnCourse = true
                Haptics.impact(.light)
                if !reduceMotion {
                    onCourseSnap = true
                    Task {
                        try? await Task.sleep(nanoseconds: 300_000_000)
                        onCourseSnap = false
                    }
                }
            } else {
                didFireOnCourse = false
            }
        }
        .accessibilityLabel({
            var text = label
            if let relBearing {
                let direction = Self.compassDirection(for: relBearing)
                text += ". " + String(format: NSLocalizedString("card.distance.bearing.a11y", comment: "Bearing direction accessibility"), direction)
            }
            if let meters = distanceMeters, ProximityTint.from(meters: meters) == .near {
                text += ". " + NSLocalizedString("card.distance.proximity.near", comment: "VoiceOver proximity cue when close")
            }
            if isOnCourse {
                text += ". " + NSLocalizedString("card.distance.onCourse.a11y", comment: "On course accessibility label appended to distance pill")
            }
            return text
        }())
    }

    @ViewBuilder
    private func etaPill(meters: Double) -> some View {
        let minutes = Int((meters / Self.walkMetersPerMin).rounded(.up))
        let arrival = clock.tick.addingTimeInterval(Double(minutes) * 60)
        let timeString = Self.etaFormatter.string(from: arrival)
        let label = String(format: NSLocalizedString("card.eta", comment: "ETA pill"), timeString)
        let a11y = String(format: NSLocalizedString("card.eta.a11y", comment: "ETA pill accessibility"), timeString)
        Label(label, systemImage: "figure.walk.arrival")
            .font(.caption)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .foregroundStyle(Color.green)
            .background(Capsule().fill(Color.green.opacity(0.12)))
            .contentTransition(reduceMotion ? .identity : .numericText())
            .accessibilityLabel(a11y)
    }

    @ViewBuilder
    private var arrivedPill: some View {
        Label(
            NSLocalizedString("card.distance.arrived", comment: "You're here pill label"),
            systemImage: "location.fill"
        )
        .font(.caption)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .foregroundStyle(Color.green)
        .background(Capsule().fill(Color.green.opacity(0.15)))
        .scaleEffect(arrivedPulse ? 1.0 : 0.85)
        .onAppear {
            if reduceMotion {
                arrivedPulse = true
            } else {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.6)) {
                    arrivedPulse = true
                }
            }
        }
    }

    @ViewBuilder
    private func directionsControl(coordinate: CLLocationCoordinate2D) -> some View {
        let apps = availableNavigationApps
        let name = experience.title
        if !apps.isEmpty {
            let pillLabel = Label(
                NSLocalizedString("action.directions", comment: "Directions button"),
                systemImage: "arrow.triangle.turn.up.right.diamond.fill"
            )
            .font(.caption)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .foregroundStyle(Color.accentColor)
            .background(Capsule().fill(Color.accentColor.opacity(0.12)))

            if apps.count == 1, let app = apps.first {
                Button {
                    Haptics.impact(.light)
                    NavigationLauncher.open(app: app, coordinate: coordinate, name: name)
                } label: {
                    pillLabel
                }
                .buttonStyle(.plain)
                .contentShape(Capsule())
            } else {
                Menu {
                    ForEach(apps) { app in
                        Button(app.displayName) {
                            Haptics.impact(.light)
                            NavigationLauncher.open(app: app, coordinate: coordinate, name: name)
                        }
                    }
                } label: {
                    pillLabel
                }
                .buttonStyle(.plain)
                .contentShape(Capsule())
            }
        }
    }

    /// Right-aligned "more" menu in the card header. Offers the single-card
    /// deep cross-compile (Approach A). Hidden when no handler is wired or when
    /// the place has no coordinate to compile around. Shows a spinner in place
    /// of the ellipsis while this card is being re-compiled.
    @ViewBuilder
    private var recompileMenu: some View {
        if let onRecompile, experience.coordinate != nil {
            if isRecompiling {
                ProgressView()
                    .progressViewStyle(.circular)
                    .controlSize(.small)
                    .frame(width: 28, height: 28)
                    .accessibilityLabel(Text(NSLocalizedString("recompile.inProgress", comment: "Cross-compile in progress")))
            } else {
                Menu {
                    Button {
                        Haptics.impact(.light)
                        onRecompile()
                    } label: {
                        Label(
                            NSLocalizedString("recompile.action", comment: "Deep cross-compile menu item"),
                            systemImage: "sparkle.magnifyingglass"
                        )
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.title3)
                        .foregroundStyle(Color.secondary)
                        .frame(
                            minWidth: HitTargetMetrics.minimum,
                            minHeight: HitTargetMetrics.minimum
                        )
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text(NSLocalizedString("recompile.action.a11y", comment: "Deep cross-compile accessibility label")))
            }
        }
    }

    @ViewBuilder
    private func bestTimeHintPill(_ hint: String) -> some View {
        Label(
            String(format: NSLocalizedString("experience.bestTime.hint", comment: "Best time hint"), hint),
            systemImage: "clock"
        )
        .font(.caption)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .foregroundStyle(Color.secondary)
        .background(Capsule().fill(Color.secondary.opacity(0.12)))
        .symbolEffect(.bounce, value: clockNudge)
        .scaleEffect(bestTimeAppeared ? 1 : 0.85)
        .opacity(bestTimeAppeared ? 1 : 0)
        .onAppear {
            if reduceMotion {
                bestTimeAppeared = true
            } else {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) {
                    bestTimeAppeared = true
                }
                clockNudge.toggle()
            }
        }
    }

    // Severity order: safety > scam > weather > crowds > logistics > etiquette > other
    private static let inconvenienceSeverity: [RealInconvenience.Category] = [
        .safety, .scam, .weather, .crowds, .logistics, .etiquette, .other
    ]

    private var mostSevereInconvenience: RealInconvenience.Category? {
        let categories = Set(experience.realInconveniences.map(\.category))
        return Self.inconvenienceSeverity.first { categories.contains($0) }
    }

    @ViewBuilder
    private var inconveniencePill: some View {
        if let category = mostSevereInconvenience {
            let isHighSeverity = category == .safety || category == .scam
            let tint = isHighSeverity ? Color.red : Color(red: 0xF5/255, green: 0x9E/255, blue: 0x0B/255)
            let count = experience.realInconveniences.count
            let a11yFormat = isHighSeverity
                ? NSLocalizedString("inconvenience.card.count.a11y.high", comment: "High-severity inconvenience pill accessibility label")
                : NSLocalizedString("inconvenience.card.count.a11y.normal", comment: "Normal inconvenience pill accessibility label")
            Label(
                String(format: NSLocalizedString("inconvenience.card.count", comment: "Inconvenience count on card"), count),
                systemImage: category.symbol
            )
            .font(.caption)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .foregroundStyle(tint)
            .background(Capsule().fill(tint.opacity(0.12)))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(String(format: a11yFormat, count, category.label))
        }
    }
}

// MARK: - BestNowBadge

private struct BestNowBadge: View {
    /// The experience to query for live countdown; the shared `BestNowClock`
    /// drives recomputation of `minutesLeftInBestWindow()` once a minute.
    var experience: Experience

    private static let gold = Color(red: 0xD4/255, green: 0xA8/255, blue: 0x43/255)
    private static let amber = Color(red: 0xF5/255, green: 0x9E/255, blue: 0x0B/255)
    private static let closingSoonThresholdMinutes = 45

    @State private var pulse = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Single 60s clock shared across every badge (US-023). Replaces the
    /// per-badge `TimelineView(.periodic(by: 60))` so 20+ badges no longer spin
    /// up 20+ concurrent timelines.
    @Environment(BestNowClock.self) private var clock

    private func isClosingSoon(at date: Date) -> Bool {
        (experience.minutesLeftInBestWindow(at: date) ?? .max) <= Self.closingSoonThresholdMinutes
    }

    private func labelText(at date: Date) -> String {
        if let minutes = experience.minutesLeftInBestWindow(at: date) {
            if isClosingSoon(at: date) {
                return String(format: NSLocalizedString("experience.bestNow.closingSoon", comment: "Closing soon with countdown"), minutes)
            }
            return String(format: NSLocalizedString("experience.bestNow.countdown", comment: "Best now with countdown"), minutes)
        }
        return NSLocalizedString("experience.bestNow", comment: "Best now label")
    }

    private func a11yText(at date: Date) -> String {
        if let minutes = experience.minutesLeftInBestWindow(at: date) {
            if isClosingSoon(at: date) {
                return String(format: NSLocalizedString("experience.bestNow.closingSoon.a11y", comment: "Closing soon accessibility with countdown"), minutes)
            }
            return String(format: NSLocalizedString("experience.bestNow.countdown.a11y", comment: "Best now accessibility with countdown"), minutes)
        }
        return NSLocalizedString("experience.bestNow", comment: "Best now label")
    }

    var body: some View {
        let closingSoon = isClosingSoon(at: clock.tick)
        let pulseDuration = closingSoon ? 0.7 : 1.1
        Group {
            if reduceMotion {
                badgeLabel(at: clock.tick)
                    .accessibilityLabel(a11yText(at: clock.tick))
            } else {
                // Reading `clock.tick` here makes this badge a SwiftUI observer
                // of the shared clock: the once-a-minute advance invalidates the
                // body and recomputes the countdown — same cadence the old
                // per-badge TimelineView gave, with one timer for all badges.
                badgeLabel(at: clock.tick)
                    .accessibilityLabel(a11yText(at: clock.tick))
                    .onAppear {
                        withAnimation(.easeInOut(duration: pulseDuration).repeatForever(autoreverses: true)) {
                            pulse = true
                        }
                    }
                    .onChange(of: closingSoon) { _, _ in
                        pulse = false
                        withAnimation(.easeInOut(duration: pulseDuration).repeatForever(autoreverses: true)) {
                            pulse = true
                        }
                    }
            }
        }
    }

    private func badgeLabel(at date: Date) -> some View {
        let closingSoon = isClosingSoon(at: date)
        let tint = closingSoon ? Self.amber : Self.gold
        let symbol = closingSoon ? "clock.badge.exclamationmark" : "sparkle"
        return Label(labelText(at: date), systemImage: symbol)
            .font(.caption)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Capsule().fill(tint.opacity(0.2)))
            .foregroundStyle(tint)
            .scaleEffect(pulse ? 1.06 : 1.0)
            .shadow(color: tint.opacity(pulse ? 0.55 : 0.0), radius: pulse ? 8 : 0)
            .contentTransition(.numericText())
    }
}

#Preview {
    if let exp = ExperienceService.hardcodedSeed.first {
        let locationService = LocationService()
        // Simulate a location ~30 m south of the seed experience so the arrived pill is visible; the bearing arrow points north toward the target.
        if let coord = exp.coordinate {
            let offset = CLLocation(latitude: coord.latitude + 0.00027, longitude: coord.longitude)
            locationService.simulate(location: offset)
        }
        return AnyView(VStack {
            Spacer()
            ExperienceCardView(
                experience: exp,
                onExpand: {},
                onDismiss: {}
            )
        }
        .background(Color(red: 0xF5/255, green: 0xF0/255, blue: 0xE8/255))
        .environment(UserPreferences(defaults: UserDefaults(suiteName: "preview")!))
        .environment(locationService)
        .environment(BestNowClock())
        .environment(AIService()))
    } else {
        return AnyView(Text("No seed data"))
    }
}

#Preview("Accessibility3 — pills wrap") {
    if let exp = ExperienceService.hardcodedSeed.first {
        let locationService = LocationService()
        if let coord = exp.coordinate {
            let offset = CLLocation(latitude: coord.latitude + 0.00027, longitude: coord.longitude)
            locationService.simulate(location: offset)
        }
        return AnyView(VStack {
            Spacer()
            ExperienceCardView(
                experience: exp,
                onExpand: {},
                onDismiss: {}
            )
        }
        .background(Color(red: 0xF5/255, green: 0xF0/255, blue: 0xE8/255))
        .environment(UserPreferences(defaults: UserDefaults(suiteName: "preview-a11y")!))
        .environment(locationService)
        .environment(AIService())
        .environment(\.dynamicTypeSize, .accessibility3))
    } else {
        return AnyView(Text("No seed data"))
    }
}
