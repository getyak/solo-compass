import SwiftUI
import CoreLocation

// MARK: - StopsList

/// Ordered list of stops for a route.
///
/// Each row shows a 36×36 category disc, title + romanized subtitle, and
/// the walking distance from the previous stop (or "Start" for the first).
/// Rows are connected by a 1 pt vertical line drawn left of each disc.
public struct StopsList: View {
    let route: Route
    let onTapStop: (Experience) -> Void

    @Environment(ExperienceService.self) private var service

    private var stops: [Experience] {
        route.experienceIds.compactMap { service.getExperience(id: $0) }
    }

    public init(route: Route, onTapStop: @escaping (Experience) -> Void) {
        self.route = route
        self.onTapStop = onTapStop
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(stops.enumerated()), id: \.offset) { index, experience in
                StopRow(
                    experience: experience,
                    distanceText: distanceLabel(index: index),
                    isLast: index == stops.count - 1
                )
                .contentShape(Rectangle())
                .onTapGesture { onTapStop(experience) }
            }
        }
    }

    private func distanceLabel(index: Int) -> String {
        guard index > 0 else {
            return NSLocalizedString("stops.start", comment: "First stop label")
        }
        let prev = stops[index - 1]
        let curr = stops[index]
        guard let a = prev.coordinate, let b = curr.coordinate else { return "—" }
        let meters = CLLocation(latitude: a.latitude, longitude: a.longitude)
            .distance(from: CLLocation(latitude: b.latitude, longitude: b.longitude))
        return formatDistance(meters)
    }

    private func formatDistance(_ meters: Double) -> String {
        if meters < 1000 {
            return String(format: "%dm", Int(meters.rounded()))
        } else {
            return String(format: "%.1fkm", meters / 1000)
        }
    }
}

// MARK: - StopRow

private struct StopRow: View {
    let experience: Experience
    let distanceText: String
    let isLast: Bool

    private let discSize: CGFloat = 36

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            connectorColumn
            textColumn
            Spacer(minLength: 0)
            chevron
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 16)
    }

    /// Left-column: disc + vertical line below it (omitted for the last stop).
    private var connectorColumn: some View {
        VStack(spacing: 0) {
            categoryDisc
            if !isLast {
                Rectangle()
                    .fill(Color(.separator))
                    .frame(width: 1)
                    .frame(maxHeight: .infinity)
                    .padding(.vertical, 2)
            }
        }
        .frame(width: discSize)
    }

    private var categoryDisc: some View {
        ZStack {
            Circle()
                .fill(experience.category.color)
                .frame(width: discSize, height: discSize)
            Image(systemName: experience.category.symbol)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white)
        }
    }

    // MARK: Right column: title + romanized name + distance

    private var textColumn: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(experience.title)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)

            if let romanized = experience.location.placeNameRomanized {
                Text(romanized)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }

            Text(distanceText)
                .font(.system(size: 12).monospacedDigit())
                .foregroundStyle(.secondary)
                .padding(.top, 2)
        }
    }

    private var chevron: some View {
        Image(systemName: "chevron.right")
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(Color(.tertiaryLabel))
            .padding(.top, 4)
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
        title: "Mekong Sunset",
        summary: "A 45-minute promenade walk that ends on a plastic chair facing Thailand.",
        experienceIds: ["exp_vte_mekong_riverside_sunset", "exp_vte_wat_si_saket_morning"],
        cityCode: "VTE",
        region: "Riverfront",
        estimatedDuration: 90,
        distanceMeters: 1200,
        pace: .relaxed,
        source: .editorial,
        verification: RouteVerification(status: .walkedBy, walkedByCount: 12, walkedBy: ["maya", "leo"])
    )

    let service = ExperienceService(seed: [mekongExp, watExp])

    ScrollView {
        StopsList(route: route, onTapStop: { _ in })
    }
    .environment(service)
    .background(Color(.systemGroupedBackground))
}
