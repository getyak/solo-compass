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
    /// Optional: tap handler for the distance/bearing pill. Fires with the
    /// experience's coordinate so the map can recenter on it.
    var onRecenter: ((CLLocationCoordinate2D) -> Void)? = nil

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
        isRecompiling: Bool = false,
        onRecenter: ((CLLocationCoordinate2D) -> Void)? = nil
    ) {
        self.experience = experience
        self.onExpand = onExpand
        self.onDismiss = onDismiss
        self.onRecompile = onRecompile
        self.isRecompiling = isRecompiling
        self.onRecenter = onRecenter
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
                categoryThumbnail

                VStack(alignment: .leading, spacing: 2) {
                    // Rounded display face — keeps the card title visually
                    // continuous with the redesigned detail page's hero title.
                    Text(experience.title)
                        .font(.system(.headline, design: .rounded, weight: .semibold))
                        .lineLimit(2)
                    Text(experience.location.placeNameRomanized ?? experience.location.addressHint ?? "")
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer()
                Button {
                    let wasFavorited = preferences.isFavorited(experience.id)
                    withAnimation(.spring(response: 0.3)) {
                        preferences.toggleFavorite(experience.id)
                    }
                    if !wasFavorited {
                        Haptics.notify(.success)
                        heartBounce += 1
                        if !reduceMotion {
                            heartBurst = true
                            Task {
                                try? await Task.sleep(nanoseconds: 450_000_000)
                                heartBurst = false
                            }
                        }
                        UIAccessibility.post(
                            notification: .announcement,
                            argument: NSLocalizedString("card.favorite.added.a11y", comment: "VoiceOver announcement when experience is saved to favorites")
                        )
                    } else {
                        Haptics.impact(.light)
                        UIAccessibility.post(
                            notification: .announcement,
                            argument: NSLocalizedString("card.favorite.removed.a11y", comment: "VoiceOver announcement when experience is removed from favorites")
                        )
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
                // Category-specific scannable facts (Wi-Fi, signature, best
                // light…). Placed right after the score so the detail that
                // matters for *this* kind of place reads before distance/ETA.
                ForEach(experience.highlights) { highlight in
                    highlightPill(highlight)
                }
                distancePillGroup
                    .contentTransition(.numericText())
                    .animation(.spring(response: 0.4), value: distanceMeters)
                if let meters = distanceMeters, !isArrived, meters < Self.walkThresholdMeters {
                    etaPill(meters: meters)
                }
                if !experience.realInconveniences.isEmpty {
                    inconveniencePill
                } else if experience.isBestNow() {
                    BestNowBadge(experience: experience)
                } else if let hint = experience.bestTimeHint(at: clock.tick) {
                    bestTimeHintPill(
                        hint,
                        opensInMinutes: experience.minutesUntilNextBestWindow(at: clock.tick),
                        isTomorrow: experience.nextBestWindowIsTomorrow(at: clock.tick)
                    )
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
        // Grabber handle: signals both swipe-up-to-expand and swipe-down-to-dismiss.
        .overlay(alignment: .top) {
            grabberHandle
        }
        // Explicit dismiss affordance: swipe-down worked but had no visible
        // cue, so the floating card felt "stuck" (it also lingered after the
        // detail sheet closed). A small × in the corner gives users a clear way
        // out without discovering the gesture.
        .overlay(alignment: .topTrailing) {
            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.secondary)
                    .frame(width: 26, height: 26)
                    .background(Circle().fill(.regularMaterial))
                    .frame(
                        minWidth: HitTargetMetrics.minimum,
                        minHeight: HitTargetMetrics.minimum
                    )
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text(NSLocalizedString("card.dismiss", comment: "Dismiss the floating experience card")))
        }
        // `totalOffset` already includes `dragOffset`; the second
        // `.offset(y: dragOffset)` double-applied the drag (and the second
        // `.opacity` darkened the card twice). Apply each exactly once.
        .offset(y: totalOffset)
        .opacity(dragOpacity)
        .padding(.horizontal, 12)
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
            let wasFavorited = isFavorited
            preferences.toggleFavorite(experience.id)
            if !wasFavorited {
                Haptics.notify(.success)
                UIAccessibility.post(
                    notification: .announcement,
                    argument: NSLocalizedString("card.favorite.added.a11y", comment: "VoiceOver announcement when experience is saved to favorites")
                )
            } else {
                Haptics.impact(.light)
                UIAccessibility.post(
                    notification: .announcement,
                    argument: NSLocalizedString("card.favorite.removed.a11y", comment: "VoiceOver announcement when experience is removed from favorites")
                )
            }
        }
        .accessibilityAction(named: Text(NSLocalizedString("action.directions", comment: "Directions accessibility action"))) {
            guard let coord = experience.coordinate,
                  let app = availableNavigationApps.first else { return }
            NavigationLauncher.open(app: app, coordinate: coord, name: experience.title)
        }
    }

    /// Grabber capsule centered at the card's top edge. Subtly widens and
    /// brightens as the user drags, reinforcing direct manipulation. Static
    /// under Reduce Motion. Hidden from VoiceOver — gestures are exposed via
    /// accessibilityHint and accessibilityActions on the card element.
    @ViewBuilder
    private var grabberHandle: some View {
        let drag = abs(dragState.translation)
        let progress = reduceMotion ? 0 : min(1, drag / 120)
        let handleWidth = 36 + progress * 8   // 36 → 44 pt
        let opacity = 0.35 + progress * 0.25  // 0.35 → 0.60
        Capsule()
            .fill(Color.secondary.opacity(opacity))
            .frame(width: handleWidth, height: 5)
            .padding(.top, 8)
            .animation(reduceMotion ? nil : .interactiveSpring(), value: dragState.translation)
            .accessibilityHidden(true)
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

    /// The distance/arrived pill, optionally wrapped in a recenter Button.
    @ViewBuilder
    private var distancePillGroup: some View {
        if let recenter = onRecenter, let coord = experience.coordinate {
            Button {
                Haptics.impact(.light)
                recenter(coord)
            } label: {
                rawDistancePill
            }
            .buttonStyle(.plain)
            .contentShape(Capsule())
            .accessibilityHint(Text(NSLocalizedString("card.distance.recenter.hint", comment: "Double tap to center the map on this experience")))
            .accessibilityAction(named: Text(NSLocalizedString("card.distance.recenter.hint", comment: "Double tap to center the map on this experience"))) {
                Haptics.impact(.light)
                recenter(coord)
            }
        } else {
            rawDistancePill
        }
    }

    @ViewBuilder
    private var rawDistancePill: some View {
        if isArrived {
            arrivedPill
        } else if let meters = distanceMeters {
            let dl = Self.formatDistance(meters)
            distancePill(dl.text, symbol: dl.symbol)
        }
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

    /// Static best-time hint ("Best 7–9am"). When the window opens within the
    /// next ~90 min, `opensInMinutes` is non-nil and the pill warms to amber with
    /// an "· opens in 25m" tail so an imminent window reads differently from one
    /// that's still hours out (which the bare gray pill could not convey).
    ///
    /// When `isTomorrow` is true the soonest occurrence of the hinted window is
    /// the following morning (every window today has already started), so a
    /// "· tomorrow" tail is appended — otherwise "Best 7–9am" at 11pm reads
    /// identically to the same hint at 8am. `isTomorrow` and the imminent case
    /// are mutually exclusive (an imminent window is, by definition, later
    /// today), and the imminent tail wins if both were ever set.
    @ViewBuilder
    private func bestTimeHintPill(_ hint: String, opensInMinutes: Int? = nil, isTomorrow: Bool = false) -> some View {
        let isImminent = opensInMinutes != nil
        let showTomorrow = isTomorrow && !isImminent
        let tint = isImminent ? Self.bestTimeImminentAmber : Color.secondary
        let label: String = {
            let base = String(format: NSLocalizedString("experience.bestTime.hint", comment: "Best time hint"), hint)
            if let mins = opensInMinutes {
                let tail = String(format: NSLocalizedString("experience.bestTime.opensIn", comment: "Best time window opens in N minutes tail"), mins)
                return "\(base) · \(tail)"
            }
            if showTomorrow {
                let tail = NSLocalizedString("experience.bestTime.tomorrow", comment: "Best time window next opens tomorrow tail")
                return "\(base) · \(tail)"
            }
            return base
        }()
        let a11y: String = {
            let base = String(format: NSLocalizedString("experience.bestTime.hint.a11y", comment: "Best time accessibility"), hint)
            if let mins = opensInMinutes {
                return base + ". " + String(format: NSLocalizedString("experience.bestTime.opensIn.a11y", comment: "Best time opens in N minutes accessibility"), mins)
            }
            if showTomorrow {
                return base + ". " + NSLocalizedString("experience.bestTime.tomorrow.a11y", comment: "Best time next opens tomorrow accessibility")
            }
            return base
        }()
        Label(label, systemImage: isImminent ? "clock.badge" : "clock")
            .font(.caption)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .foregroundStyle(tint)
            .background(Capsule().fill(tint.opacity(isImminent ? 0.16 : 0.12)))
            .symbolEffect(.bounce, value: clockNudge)
            .scaleEffect(bestTimeAppeared ? 1 : 0.85)
            .opacity(bestTimeAppeared ? 1 : 0)
            .contentTransition(reduceMotion ? .identity : .numericText())
            .accessibilityLabel(a11y)
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

    private static let bestTimeImminentAmber = Color(red: 0xF5/255, green: 0x9E/255, blue: 0x0B/255)

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

    /// Leading visual: a real place photo when one resolved (OSM image /
    /// Wikimedia), with the category color as a small corner badge so the type
    /// stays scannable. Falls back to the original category-icon circle when
    /// there's no photo, so photo-less places look exactly as before.
    @ViewBuilder
    private var categoryThumbnail: some View {
        if let urlString = experience.location.photoUrls?.first,
           let url = URL(string: urlString) {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .scaledToFill()
                case .empty:
                    ZStack {
                        Rectangle().fill(experience.category.color.opacity(0.15))
                        ProgressView()
                    }
                case .failure:
                    categoryIconCircle
                @unknown default:
                    categoryIconCircle
                }
            }
            .frame(width: 52, height: 52)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            // Category color corner badge keeps the type glanceable over a photo.
            .overlay(alignment: .bottomTrailing) {
                Image(systemName: experience.category.symbol)
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 18, height: 18)
                    .background(Circle().fill(experience.category.color))
                    .overlay(Circle().stroke(.background, lineWidth: 1.5))
                    .offset(x: 3, y: 3)
            }
            .accessibilityHidden(true)
        } else {
            categoryIconCircle
        }
    }

    /// The original category-icon circle, reused for photo-less places and as
    /// the AsyncImage failure/placeholder fallback.
    private var categoryIconCircle: some View {
        Image(systemName: experience.category.symbol)
            .foregroundStyle(.white)
            .frame(width: 32, height: 32)
            .background(Circle().fill(experience.category.color))
    }

    /// A category-specific highlight pill (Wi-Fi · fast, Signature · pho bo…).
    /// Mirrors the existing pill styling (caption, tinted capsule) for a
    /// consistent FlowLayout row. Uses the secondary label tint so it reads as
    /// neutral context, not an alert.
    private func highlightPill(_ highlight: CategoryHighlight) -> some View {
        HStack(spacing: 4) {
            Image(systemName: highlight.kind.symbol)
                .font(.caption2)
            Text(highlight.value)
                .font(.caption)
                .lineLimit(1)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .foregroundStyle(.secondary)
        .background(Capsule().fill(Color.secondary.opacity(0.12)))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(highlight.label): \(highlight.value)")
    }
}

// MARK: - BestNowBadge

// `internal` (not `private`) so `BestNowBadge.reasonSubtitle` is reachable from
// `BestNowBadgeReasonTests` via `@testable import` (US-007).
struct BestNowBadge: View {
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

    /// US-007: the one-line reason subtitle for a `NowScore`, falling back to the
    /// localized "此刻" label when the score carries no explanation. The top-3 +
    /// truncation rule lives in `Experience.nowReasonSubtitle` so it is unit
    /// testable without touching this private view.
    static func reasonSubtitle(for score: NowScore) -> String {
        Experience.nowReasonSubtitle(for: score)
            ?? NSLocalizedString("badge.now.fallback", comment: "Fallback reason subtitle when NowScore has no explanation")
    }

    var body: some View {
        let closingSoon = isClosingSoon(at: clock.tick)
        let pulseDuration = closingSoon ? 0.7 : 1.1
        VStack(alignment: .leading, spacing: 3) {
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
            reasonSubtitle(at: clock.tick)
        }
    }

    /// US-007: a muted, one-line reason beneath the badge label explaining WHY
    /// this experience is "best now". Rendered only when the live NowScore clears
    /// the 0.7 threshold; otherwise the badge keeps its prior label-only form.
    @ViewBuilder
    private func reasonSubtitle(at date: Date) -> some View {
        let score = experience.nowScore(at: date)
        if score.value >= 0.7 {
            Text(Self.reasonSubtitle(for: score))
                .font(CT.body(11, .medium))
                .foregroundStyle(CT.fgMuted)
                .lineLimit(1)
                .accessibilityHidden(true)
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

#Preview("Grabber handle — at rest") {
    if let exp = ExperienceService.hardcodedSeed.first {
        return AnyView(VStack {
            Spacer()
            ExperienceCardView(
                experience: exp,
                onExpand: {},
                onDismiss: {}
            )
        }
        .background(Color(red: 0xF5/255, green: 0xF0/255, blue: 0xE8/255))
        .environment(UserPreferences(defaults: UserDefaults(suiteName: "preview-grabber")!))
        .environment(LocationService())
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
