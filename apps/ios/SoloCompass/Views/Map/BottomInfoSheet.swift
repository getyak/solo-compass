import SwiftUI
import CoreLocation

// MARK: - Constants

private let peekHeight: CGFloat = 170
private let midHeight: CGFloat = 500
private let fullHeight: CGFloat = 800
private let minHeight: CGFloat = 120
private let maxHeight: CGFloat = 830
private let cornerRadius: CGFloat = 20
private let scrimMaxOpacity: CGFloat = 0.18

// MARK: - Detent

enum BottomSheetDetent {
    case peek, mid, full

    var height: CGFloat {
        switch self {
        case .peek: return peekHeight
        case .mid: return midHeight
        case .full: return fullHeight
        }
    }

    static func nearest(to height: CGFloat) -> BottomSheetDetent {
        let all: [BottomSheetDetent] = [.peek, .mid, .full]
        return all.min(by: { abs($0.height - height) < abs($1.height - height) }) ?? .peek
    }
}

// MARK: - BottomInfoSheet

public struct BottomInfoSheet<Content: View>: View {
    @State private var currentDetent: BottomSheetDetent = .peek
    @State private var dragOffset: CGFloat = 0
    @State private var isDragging: Bool = false

    private let aiHint: String
    private let count: Int
    private let isNowMode: Bool
    private let content: (BottomSheetDetent) -> Content

    public init(
        aiHint: String,
        count: Int,
        isNowMode: Bool,
        @ViewBuilder content: @escaping (BottomSheetDetent) -> Content
    ) {
        self.aiHint = aiHint
        self.count = count
        self.isNowMode = isNowMode
        self.content = content
    }

    private var baseHeight: CGFloat { currentDetent.height }

    private var displayHeight: CGFloat {
        let h = baseHeight - dragOffset
        return max(minHeight, min(maxHeight, h))
    }

    private var scrimOpacity: CGFloat {
        let fraction = (displayHeight - peekHeight) / (fullHeight - peekHeight)
        return max(0, min(1, fraction)) * scrimMaxOpacity
    }

    public var body: some View {
        ZStack(alignment: .bottom) {
            // Map scrim overlay
            Color.black
                .opacity(scrimOpacity)
                .ignoresSafeArea()
                .allowsHitTesting(false)

            // Sheet
            VStack(spacing: 0) {
                dragHandleArea
                NowHintRow(hint: aiHint)
                    .padding(.horizontal, 16)
                    .padding(.top, 6)
                SortCountToolbar(count: count, isNowMode: isNowMode)
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                content(currentDetent)
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity)
            .frame(height: displayHeight)
            .background(
                UnevenRoundedRectangle(
                    topLeadingRadius: cornerRadius,
                    bottomLeadingRadius: 0,
                    bottomTrailingRadius: 0,
                    topTrailingRadius: cornerRadius
                )
                .fill(.ultraThinMaterial)
            )
        }
        .animation(isDragging ? nil : .spring(response: 0.3, dampingFraction: 0.85), value: displayHeight)
    }

    // MARK: - Drag Handle

    private var dragHandleArea: some View {
        // 24×16 pt hit area containing a 36×4 pill
        ZStack {
            Color.clear
                .frame(width: 24, height: 16)
                .contentShape(Rectangle())

            Capsule()
                .fill(Color.secondary.opacity(0.5))
                .frame(width: 36, height: 4)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 8)
        .gesture(
            DragGesture(minimumDistance: 4)
                .onChanged { value in
                    isDragging = true
                    dragOffset = value.translation.height
                }
                .onEnded { value in
                    isDragging = false
                    let projectedHeight = baseHeight - value.predictedEndTranslation.height
                    let clampedHeight = max(minHeight, min(maxHeight, projectedHeight))
                    currentDetent = BottomSheetDetent.nearest(to: clampedHeight)
                    dragOffset = 0
                }
        )
    }
}

// MARK: - NowHintRow

struct NowHintRow: View {
    let hint: String

    private var timeString: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: Date())
    }

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "sunset.fill")
                .font(.caption)
                .foregroundStyle(.orange)
            Text(hint)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Spacer(minLength: 4)
            Text(timeString)
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text("\(hint) \(timeString)"))
    }
}

// MARK: - SortCountToolbar

struct SortCountToolbar: View {
    let count: Int
    let isNowMode: Bool

    var body: some View {
        HStack {
            sortButton
            Spacer()
            countBadge
        }
    }

    private var sortButton: some View {
        Button {
            // Sort dropdown — behavior added in a follow-up story
        } label: {
            HStack(spacing: 4) {
                Text(NSLocalizedString("sheet.sort.button", comment: "Sort"))
                    .font(.caption.weight(.medium))
                Image(systemName: "chevron.down")
                    .font(.caption2.weight(.semibold))
            }
            .foregroundStyle(.primary)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Capsule().fill(.regularMaterial))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(NSLocalizedString("sheet.sort.button", comment: "Sort")))
    }

    private var countBadge: some View {
        let key = isNowMode ? "sheet.count.now" : "sheet.count.nearby"
        let label = String(
            format: NSLocalizedString(key, comment: "Count badge"),
            count
        )
        return Text(label)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Capsule().fill(Color.secondary.opacity(0.12)))
            .accessibilityLabel(Text(label))
    }
}

// MARK: - NearbyExperienceRow

/// Single row in the '附近' section of the BottomInfoSheet.
/// Layout: 36×36 category disc | title + romanized + local | mono distance + compass arrow
struct NearbyExperienceRow: View {
    let experience: Experience
    let isSmartPick: Bool
    /// Distance in meters from the user's current location (or map center).
    let distanceMeters: Double?
    let onTap: () -> Void

    private static let sunGold = Color(red: 1.0, green: 0.80, blue: 0.2)

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 10) {
                categoryDisc
                titleStack
                Spacer(minLength: 4)
                distancePill
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(rowBackground)
            .overlay(alignment: .leading) {
                if isSmartPick {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Self.sunGold)
                        .frame(width: 3)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityHint(Text(NSLocalizedString("experience.card.hint", comment: "Double tap to view details")))
    }

    // MARK: - Sub-views

    private var categoryDisc: some View {
        ZStack {
            Circle()
                .fill(experience.category.color.opacity(0.18))
                .frame(width: 36, height: 36)
            Image(systemName: experience.category.symbol)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(experience.category.color)
        }
    }

    @ViewBuilder
    private var titleStack: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(experience.title)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.primary)
                .lineLimit(1)

            let sub = subtitleText
            if !sub.isEmpty {
                Text(sub)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
    }

    private var subtitleText: String {
        let parts = [
            experience.location.placeNameRomanized,
            experience.location.placeNameLocal
        ].compactMap { $0?.isEmpty == false ? $0 : nil }
        if parts.isEmpty {
            return experience.location.addressHint ?? ""
        }
        return parts.joined(separator: " · ")
    }

    private var distancePill: some View {
        HStack(spacing: 3) {
            if let meters = distanceMeters {
                Text(formattedDistance(meters))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            Image(systemName: "location.north.line.fill")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
    }

    @ViewBuilder
    private var rowBackground: some View {
        if isSmartPick {
            LinearGradient(
                colors: [
                    Self.sunGold.opacity(0.10),
                    Self.sunGold.opacity(0.04)
                ],
                startPoint: .leading,
                endPoint: .trailing
            )
        } else {
            Color.clear
        }
    }

    private var accessibilityLabel: Text {
        var label = experience.title
        if let meters = distanceMeters {
            label += ", \(formattedDistance(meters))"
        }
        if isSmartPick {
            label += ", " + NSLocalizedString("sheet.nearby.smartPick.a11y", comment: "AI pick")
        }
        return Text(label)
    }

    private func formattedDistance(_ meters: Double) -> String {
        if meters < 1000 {
            return String(format: "%dm", Int(meters))
        } else {
            return String(format: "%.1fkm", meters / 1000)
        }
    }
}

// MARK: - NearbySection

/// '附近' section rendered inside BottomInfoSheet when detent > .peek.
/// Smart sort: AI top-3 pinned at top (sun-gold border + warm gradient),
/// remaining sorted by distance ascending.
struct NearbySection: View {
    let experiences: [Experience]
    /// IDs of AI-ranked top picks (up to 3 pinned at top).
    let smartPickIds: [String]
    /// Reference coordinate for distance calculation (user location or map center).
    let referenceCoordinate: CLLocationCoordinate2D?
    let onSelectExperience: (Experience) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionHeader
            Divider()
                .padding(.horizontal, 16)
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(sortedExperiences) { exp in
                        NearbyExperienceRow(
                            experience: exp,
                            isSmartPick: smartPickIds.contains(exp.id),
                            distanceMeters: distance(to: exp),
                            onTap: { onSelectExperience(exp) }
                        )
                        Divider()
                            .padding(.leading, 62)
                    }
                }
            }
        }
        .padding(.top, 8)
    }

    private var sectionHeader: some View {
        Text(NSLocalizedString("sheet.nearby.section.title", comment: "Nearby section header"))
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .textCase(.uppercase)
            .tracking(0.5)
            .padding(.horizontal, 16)
            .padding(.bottom, 6)
    }

    /// Smart sort: AI picks (in ranked order) first, then remaining sorted by distance.
    private var sortedExperiences: [Experience] {
        let smartSet = Set(smartPickIds)
        let picks = smartPickIds.compactMap { id in experiences.first { $0.id == id } }
        let rest = experiences
            .filter { !smartSet.contains($0.id) }
            .sorted { lhs, rhs in
                let dl = distance(to: lhs) ?? .infinity
                let dr = distance(to: rhs) ?? .infinity
                return dl < dr
            }
        return picks + rest
    }

    private func distance(to experience: Experience) -> Double? {
        guard let ref = referenceCoordinate,
              let coord = experience.coordinate else { return nil }
        let from = CLLocation(latitude: ref.latitude, longitude: ref.longitude)
        let to = CLLocation(latitude: coord.latitude, longitude: coord.longitude)
        return from.distance(from: to)
    }
}

// MARK: - Preview

#Preview {
    ZStack(alignment: .bottom) {
        Color.teal.ignoresSafeArea()

        BottomInfoSheet(
            aiHint: NSLocalizedString("ai.now.hint", comment: "AI now hint"),
            count: 7,
            isNowMode: false
        ) { detent in
            if detent != .peek {
                Text("Nearby list goes here")
                    .padding()
            }
        }
    }
}
