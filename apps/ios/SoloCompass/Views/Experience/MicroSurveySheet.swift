import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

/// Three-question post-visit survey shown after marking an experience complete.
/// Signals feed back into soloScore recomputation (US-031/032).
/// The user can always skip — we never block navigation on survey completion.
public struct MicroSurveySheet: View {
    let experience: Experience
    var onSubmit: (_ comfort: Int, _ staffPressure: Int, _ recommend: SurveyRecommend) -> Void
    var onSkip: () -> Void

    public enum SurveyRecommend: String, CaseIterable {
        case yes, depends, no

        var label: String {
            switch self {
            case .yes:     return NSLocalizedString("survey.recommend.yes", comment: "Yes")
            case .depends: return NSLocalizedString("survey.recommend.depends", comment: "Depends")
            case .no:      return NSLocalizedString("survey.recommend.no", comment: "No")
            }
        }
        var symbol: String {
            switch self {
            case .yes:     return "hand.thumbsup.fill"
            case .depends: return "hand.wave.fill"
            case .no:      return "hand.thumbsdown.fill"
            }
        }
        var color: Color {
            switch self {
            case .yes:     return .green
            case .depends: return .orange
            case .no:      return .red
            }
        }
    }

    @State private var comfort: Int = 3
    @State private var staffPressure: Int = 3
    @State private var recommend: SurveyRecommend = .yes

    public init(
        experience: Experience,
        onSubmit: @escaping (_ comfort: Int, _ staffPressure: Int, _ recommend: SurveyRecommend) -> Void,
        onSkip: @escaping () -> Void
    ) {
        self.experience = experience
        self.onSubmit = onSubmit
        self.onSkip = onSkip
    }

    public var body: some View {
        VStack(spacing: 0) {
            RoundedRectangle(cornerRadius: 3)
                .fill(Color(.systemGray4))
                .frame(width: 36, height: 5)
                .padding(.top, 12)
                .padding(.bottom, 8)

            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    headerSection
                    comfortQuestion
                    staffPressureQuestion
                    recommendQuestion
                    actionButtons
                }
                .padding(.horizontal, 24)
                .padding(.top, 8)
                .padding(.bottom, 40)
            }
        }
        .background(Color(.systemBackground))
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.hidden)
    }

    // MARK: - Sections

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(NSLocalizedString("survey.title", comment: "Quick check-in"))
                .font(.title3.bold())
            Text(experience.title)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
    }

    private var comfortQuestion: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(NSLocalizedString("survey.comfort.question",
                                   comment: "How comfortable did you feel as a solo traveler?"))
                .font(.subheadline.weight(.medium))
            StarRatingRow(value: $comfort, max: 5)
            Text(comfortLabel(comfort))
                .font(.caption)
                .foregroundStyle(.secondary)
                .id(comfort)
                .transition(.opacity.combined(with: .move(edge: .bottom)))
        }
    }

    private var staffPressureQuestion: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(NSLocalizedString("survey.pressure.question",
                                   comment: "How pushy was the staff / vendors? (more stars = less pressure)"))
                .font(.subheadline.weight(.medium))
            StarRatingRow(value: $staffPressure, max: 5)
            Text(pressureLabel(staffPressure))
                .font(.caption)
                .foregroundStyle(.secondary)
                .id(staffPressure)
                .transition(.opacity.combined(with: .move(edge: .bottom)))
        }
    }

    private var recommendQuestion: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(NSLocalizedString("survey.recommend.question",
                                   comment: "Would you recommend this to another solo traveler?"))
                .font(.subheadline.weight(.medium))
            HStack(spacing: 10) {
                ForEach(SurveyRecommend.allCases, id: \.rawValue) { option in
                    recommendButton(option)
                }
            }
        }
    }

    private func recommendButton(_ option: SurveyRecommend) -> some View {
        let selected = recommend == option
        return Button {
            recommend = option
            Haptics.impact(.light)
        } label: {
            VStack(spacing: 4) {
                Image(systemName: option.symbol).font(.title3)
                Text(option.label).font(.caption.weight(.medium))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(selected ? option.color.opacity(0.15) : Color(.secondarySystemFill))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(selected ? option.color : .clear, lineWidth: 2)
            )
            .foregroundStyle(selected ? option.color : .secondary)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private var actionButtons: some View {
        VStack(spacing: 12) {
            Button {
                Haptics.notify(.success)
                onSubmit(comfort, staffPressure, recommend)
            } label: {
                Text(NSLocalizedString("survey.submit", comment: "Send feedback"))
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
                    .background(RoundedRectangle(cornerRadius: 25).fill(Color.primary))
                    .foregroundStyle(Color(.systemBackground))
            }

            Button { onSkip() } label: {
                Text(NSLocalizedString("survey.skip", comment: "Skip"))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Labels

    private func comfortLabel(_ v: Int) -> String {
        let keys = ["survey.comfort.1", "survey.comfort.2", "survey.comfort.3", "survey.comfort.4", "survey.comfort.5"]
        let defaults = ["Very uncomfortable", "Slightly uncomfortable", "Neutral", "Comfortable", "Very comfortable"]
        let idx = max(0, min(v - 1, 4))
        return NSLocalizedString(keys[idx], comment: defaults[idx])
    }

    private func pressureLabel(_ v: Int) -> String {
        // Inverted scale: 1 star = very pushy, 5 stars = no pressure (good)
        let keys = ["survey.pressure.1", "survey.pressure.2", "survey.pressure.3", "survey.pressure.4", "survey.pressure.5"]
        let defaults = ["Very pushy", "Somewhat pushy", "Neutral", "Relaxed vibe", "No pressure at all"]
        let idx = max(0, min(v - 1, 4))
        return NSLocalizedString(keys[idx], comment: defaults[idx])
    }
}

// MARK: - StarRatingRow

private struct StarRatingRow: View {
    @Binding var value: Int
    let max: Int

    @State private var poppedStar: Int?
    @State private var lastHapticStar: Int = 0

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { geo in
            let starWidth = geo.size.width / CGFloat(max)
            HStack(spacing: 0) {
                ForEach(1...max, id: \.self) { star in
                    Button {
                        setStar(star)
                    } label: {
                        Image(systemName: star <= value ? "star.fill" : "star")
                            .font(.title3)
                            .foregroundStyle(starColor(star))
                            .scaleEffect(poppedStar == star ? 1.3 : 1.0)
                            .animation(
                                reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.6),
                                value: poppedStar
                            )
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text("\(star) " + NSLocalizedString("survey.stars", comment: "stars")))
                    .accessibilityAddTraits(star == value ? .isSelected : [])
                }
            }
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { drag in
                        let rawStar = Int(floor(drag.location.x / starWidth)) + 1
                        let clamped = min(max, Swift.max(1, rawStar))
                        if clamped != lastHapticStar {
                            withAnimation(
                                reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.6)
                            ) {
                                value = clamped
                            }
                            Haptics.selection()
                            lastHapticStar = clamped
                            triggerPop(for: clamped)
                        }
                    }
                    .onEnded { _ in
                        lastHapticStar = 0
                    }
            )
        }
        .frame(height: 32)
    }

    private func setStar(_ star: Int) {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
            value = star
        }
        Haptics.impact(.rigid)
        triggerPop(for: star)
    }

    private func triggerPop(for star: Int) {
        poppedStar = star
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            poppedStar = nil
        }
    }

    private func starColor(_ star: Int) -> Color {
        guard star <= value else { return Color(.systemGray4) }
        return value <= 2 ? .red : value == 3 ? .orange : .green
    }
}

#Preview {
    Text("Preview requires ExperienceService seed")
}
