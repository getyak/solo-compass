import SwiftUI
import CoreLocation

/// Floating card that slides up when a marker is tapped. Tap → expand. Swipe
/// down → dismiss. Swipe up → full detail sheet.
public struct ExperienceCardView: View {
    let experience: Experience
    var onExpand: () -> Void
    var onDismiss: () -> Void

    private struct DragState {
        var translation: CGFloat = 0
        var hapticFired: Bool = false
    }

    @GestureState private var dragState = DragState()
    @State private var dragOffset: CGFloat = 0
    @State private var heartBounce = 0
    @State private var heartBurst = false

    private enum HapticState { case idle, prepared, fired }

    // Pre-allocated so prepare() can be called once when the drag starts.
    private let feedbackGenerator = UIImpactFeedbackGenerator(style: .medium)
    @Environment(UserPreferences.self) private var preferences
    @Environment(LocationService.self) private var locationService
    @Environment(\.accessibilityReduceMotion) private var reduceMotion


    /// Finite distance in meters, or nil when location is unknown.
    private var distanceMeters: Double? {
        guard let coord = experience.coordinate else { return nil }
        let d = locationService.distance(to: coord)
        // greatestFiniteMagnitude is the sentinel returned when no fix is available;
        // isFinite alone cannot distinguish it from a real reading.
        return (d.isFinite && d < .greatestFiniteMagnitude) ? d : nil
    }

    private static let distanceFormatter: MeasurementFormatter = {
        let f = MeasurementFormatter()
        f.unitOptions = .naturalScale
        f.unitStyle = .short
        f.numberFormatter.maximumFractionDigits = 1
        return f
    }()

    /// Formats a distance in meters into a human-readable walk-time or distance string.
    private static func formatDistance(_ meters: Double) -> String {
        let walkMetersPerMin = 80.0
        if meters < 1000 {
            let minutes = Int((meters / walkMetersPerMin).rounded(.up))
            if minutes < 1 {
                return NSLocalizedString("card.distance.walkSub1", comment: "Distance less than 1 min walk")
            }
            return String(format: NSLocalizedString("card.distance.walk", comment: "Distance in walk minutes"), minutes)
        }
        let measurement = Measurement(value: meters, unit: UnitLength.meters)
        return distanceFormatter.string(from: measurement)
    }

    public init(
        experience: Experience,
        onExpand: @escaping () -> Void,
        onDismiss: @escaping () -> Void
    ) {
        self.experience = experience
        self.onExpand = onExpand
        self.onDismiss = onDismiss
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
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
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
                    .frame(width: 32, height: 32)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(preferences.isFavorited(experience.id)
                    ? NSLocalizedString("card.favorite.remove", comment: "Remove from favorites")
                    : NSLocalizedString("card.favorite.add", comment: "Add to favorites"))
                ConfidenceBadge(confidence: experience.confidence, compact: true)
            }

            Text(experience.oneLiner)
                .font(.subheadline)
                .foregroundStyle(.primary)
                .lineLimit(3)

            HStack {
                SoloScoreBadge(score: experience.soloScore, style: .compact)
                if let meters = distanceMeters {
                    distancePill(Self.formatDistance(meters))
                }
                if !experience.realInconveniences.isEmpty {
                    inconveniencePill
                } else if experience.isBestNow() {
                    BestNowBadge()
                } else if let hint = experience.bestTimeHint() {
                    bestTimeHintPill(hint)
                }
                Spacer()
                Button(action: onExpand) {
                    Text(NSLocalizedString("experience.viewDetails", comment: "View details"))
                        .font(.subheadline.weight(.medium))
                }
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(.regularMaterial)
                .shadow(color: .black.opacity(0.1), radius: 12, y: -2)
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
                    if state.translation == 0 {
                        feedbackGenerator.prepare()
                    }
                    state.translation = t
                    if abs(t) > 60 && !state.hapticFired {
                        feedbackGenerator.impactOccurred()
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
        .onAppear {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        }
        .transition(.move(edge: .bottom).combined(with: .opacity))
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text(
            "\(experience.title). \(experience.oneLiner). " +
            String(format: NSLocalizedString("solo.a11y", comment: "Solo Score %@ of 10"),
                   String(format: "%.1f", experience.soloScore.overall)) +
            {
                var parts = ""
                if let meters = distanceMeters {
                    parts += ". " + Self.formatDistance(meters)
                }
                let count = experience.realInconveniences.count
                if count > 0 {
                    parts += ". " + String(format: NSLocalizedString("inconvenience.card.a11y", comment: "Heads up: N things to know"), count)
                } else if let hint = experience.bestTimeHint() {
                    parts += ". " + String(format: NSLocalizedString("experience.bestTime.hint.a11y", comment: "Best time accessibility"), hint)
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
    }

    @ViewBuilder
    private func distancePill(_ label: String) -> some View {
        Label(label, systemImage: "figure.walk")
            .font(.caption)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .foregroundStyle(Color.secondary)
            .background(Capsule().fill(Color.secondary.opacity(0.12)))
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
            Label(
                String(format: NSLocalizedString("inconvenience.card.count", comment: "Inconvenience count on card"), count),
                systemImage: category.symbol
            )
            .font(.caption)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .foregroundStyle(tint)
            .background(Capsule().fill(tint.opacity(0.12)))
        }
    }
}

// MARK: - BestNowBadge

private struct BestNowBadge: View {
    private static let gold = Color(red: 0xD4/255, green: 0xA8/255, blue: 0x43/255)

    @State private var pulse = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Label(NSLocalizedString("experience.bestNow", comment: ""), systemImage: "sparkle")
            .font(.caption)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Capsule().fill(Self.gold.opacity(0.2)))
            .foregroundStyle(Self.gold)
            .scaleEffect(pulse ? 1.06 : 1.0)
            .shadow(color: Self.gold.opacity(pulse ? 0.55 : 0.0), radius: pulse ? 8 : 0)
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true)) {
                    pulse = true
                }
            }
    }
}

#Preview {
    if let exp = ExperienceService.hardcodedSeed.first {
        let locationService = LocationService()
        // Simulate a location ~450 m from the seed experience so the pill is visible in preview.
        if let coord = exp.coordinate {
            let offset = CLLocation(latitude: coord.latitude + 0.004, longitude: coord.longitude)
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
        .environment(locationService))
    } else {
        return AnyView(Text("No seed data"))
    }
}
