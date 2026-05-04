import SwiftUI

/// Full-screen scrollable detail. Renders every field of the Experience model
/// the user might want before going. Real Inconveniences are surfaced as
/// prominently as the recommendation — that is the product's brand.
public struct ExperienceDetailView: View {
    @State var viewModel: ExperienceDetailViewModel
    var onClose: () -> Void

    public init(viewModel: ExperienceDetailViewModel, onClose: @escaping () -> Void = {}) {
        self.viewModel = viewModel
        self.onClose = onClose
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                heroSection
                whyItMattersSection
                bestTimesSection
                howToSection
                inconveniencesSection
                soloScoreSection
                sourcesSection
                if !viewModel.nearbyExperiences.isEmpty {
                    nearbySection
                }
                Spacer(minLength: 80)
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
        }
        .overlay(alignment: .bottom) { actionBar }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button(action: onClose) {
                    Image(systemName: "chevron.down")
                }
            }
        }
        .task { await viewModel.loadAIExplanation() }
    }

    // MARK: - Hero

    private var heroSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: viewModel.experience.category.symbol)
                    .font(.subheadline)
                    .foregroundStyle(.white)
                    .padding(6)
                    .background(Circle().fill(viewModel.experience.category.color))
                Text(viewModel.experience.category.localizedTitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer()
                ConfidenceBadge(confidence: viewModel.experience.confidence, compact: false)
            }

            Text(viewModel.experience.title)
                .font(.title2.bold())
                .fixedSize(horizontal: false, vertical: true)

            Text(viewModel.experience.oneLiner)
                .font(.body)
                .foregroundStyle(.secondary)

            if let local = viewModel.experience.location.placeNameLocal {
                Text("\(local) · \(viewModel.experience.location.placeNameRomanized ?? "")")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    // MARK: - Sections

    private var whyItMattersSection: some View {
        sectionContainer(title: NSLocalizedString("section.whyItMatters", comment: "")) {
            Text(viewModel.experience.whyItMatters)
                .font(.body)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var bestTimesSection: some View {
        sectionContainer(title: NSLocalizedString("section.bestTimes", comment: "")) {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(viewModel.experience.bestTimes, id: \.self) { window in
                    HStack(spacing: 8) {
                        Image(systemName: "clock")
                            .foregroundStyle(.secondary)
                        Text(format(window: window))
                            .font(.subheadline)
                        if let note = window.note {
                            Text(note)
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                    }
                }
                let range = viewModel.experience.durationMinutes
                Text(String(format: NSLocalizedString("section.duration", comment: ""), range.min, range.max))
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    private var howToSection: some View {
        sectionContainer(title: NSLocalizedString("section.howTo", comment: "")) {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(viewModel.experience.howTo) { step in
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Text("\(step.order)")
                            .font(.caption.bold())
                            .foregroundStyle(.white)
                            .frame(width: 20, height: 20)
                            .background(Circle().fill(viewModel.experience.category.color))
                        Text(step.text)
                            .font(.body)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }

    private var inconveniencesSection: some View {
        sectionContainer(title: NSLocalizedString("section.inconveniences", comment: "")) {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(viewModel.experience.realInconveniences) { item in
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: item.category.symbol)
                            .foregroundStyle(.orange)
                            .frame(width: 20)
                        Text(item.text)
                            .font(.subheadline)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(Color.orange.opacity(0.08))
                    )
                }
            }
        }
    }

    private var soloScoreSection: some View {
        sectionContainer(title: NSLocalizedString("section.soloScore", comment: "")) {
            SoloScoreBadge(score: viewModel.experience.soloScore, style: .full)
        }
    }

    private var sourcesSection: some View {
        sectionContainer(title: NSLocalizedString("section.sources", comment: "")) {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(viewModel.experience.sources) { source in
                    HStack {
                        Image(systemName: "link")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(source.attribution ?? source.type.rawValue)
                            .font(.caption)
                        Spacer()
                        Text(source.verifiedAt, style: .date)
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
            }
        }
    }

    private var nearbySection: some View {
        sectionContainer(title: NSLocalizedString("section.nearby", comment: "")) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(viewModel.nearbyExperiences) { exp in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Image(systemName: exp.category.symbol)
                                    .foregroundStyle(.white)
                                    .padding(6)
                                    .background(Circle().fill(exp.category.color))
                                Spacer()
                                SoloScoreBadge(score: exp.soloScore, style: .compact)
                            }
                            Text(exp.title)
                                .font(.caption.bold())
                                .lineLimit(2)
                                .multilineTextAlignment(.leading)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .padding(10)
                        .frame(width: 180, alignment: .leading)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color.gray.opacity(0.08))
                        )
                    }
                }
            }
        }
    }

    // MARK: - Action bar

    private var actionBar: some View {
        HStack(spacing: 12) {
            Button {
                viewModel.toggleFavorite()
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
            } label: {
                Image(systemName: viewModel.isFavorited ? "heart.fill" : "heart")
                    .font(.title3)
                    .foregroundStyle(viewModel.isFavorited ? .red : .primary)
                    .frame(width: 50, height: 50)
                    .background(Circle().fill(.regularMaterial))
            }
            Button {
                viewModel.toggleComplete()
                UINotificationFeedbackGenerator().notificationOccurred(.success)
            } label: {
                HStack {
                    Image(systemName: viewModel.isCompleted ? "checkmark.circle.fill" : "checkmark.circle")
                    Text(viewModel.isCompleted
                        ? NSLocalizedString("action.completed", comment: "")
                        : NSLocalizedString("action.markDone", comment: ""))
                        .font(.subheadline.weight(.medium))
                }
                .frame(maxWidth: .infinity)
                .frame(height: 50)
                .background(
                    RoundedRectangle(cornerRadius: 25)
                        .fill(viewModel.isCompleted ? Color.green : Color.black)
                )
                .foregroundStyle(.white)
            }
            Button {
                // Voice share placeholder — would record a 30s memo.
            } label: {
                Image(systemName: "mic.fill")
                    .font(.title3)
                    .frame(width: 50, height: 50)
                    .background(Circle().fill(.regularMaterial))
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 12)
    }

    // MARK: - Helpers

    private func sectionContainer<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.headline)
            content()
        }
    }

    private func format(window: TimeWindow) -> String {
        String(format: "%02d:00 – %02d:00", window.startHour, window.endHour)
    }
}

#Preview {
    let exp = ExperienceService.hardcodedSeed.first!
    let vm = ExperienceDetailViewModel(
        experience: exp,
        experienceService: ExperienceService(),
        aiService: AIService(),
        preferences: UserPreferences()
    )
    return NavigationStack {
        ExperienceDetailView(viewModel: vm) {}
    }
}
