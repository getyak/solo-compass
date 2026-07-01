import SwiftUI
import SwiftData

/// Travel Archive tab (P1.1 #111).
///
/// Three vertical bands:
/// 1. Trip summary card — current city, days, distinct Experience count.
/// 2. Timeline grouped by city, newest visit first.
/// 3. "City codex" placeholder — fills in Phase 3 #303.
public struct ArchiveView: View {

    @State private var viewModel: ArchiveViewModel

    public init(modelContainer: ModelContainer, activeCityCode: String? = nil) {
        _viewModel = State(initialValue: ArchiveViewModel(
            modelContainer: modelContainer,
            activeCityCode: activeCityCode
        ))
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                if viewModel.isEmpty {
                    emptyState
                } else {
                    if let trip = viewModel.currentTrip {
                        tripCard(trip: trip)
                    }
                    ForEach(viewModel.groups) { group in
                        citySection(group: group)
                    }
                    codexPlaceholder
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 20)
        }
        .background(Color(white: 0.98))
        .navigationTitle(NSLocalizedString("archive.title", comment: "Travel archive title"))
        .onAppear { viewModel.refresh() }
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
        VStack(spacing: 12) {
            Image(systemName: "map")
                .font(.system(size: 40))
                .foregroundStyle(CT.fgPrimary.opacity(0.3))
            Text(NSLocalizedString("archive.empty.title", comment: "Empty archive title"))
                .font(.system(.headline, design: .rounded))
                .foregroundStyle(CT.fgPrimary.opacity(0.75))
            Text(NSLocalizedString("archive.empty.subtitle", comment: "Empty archive subtitle"))
                .font(.caption)
                .foregroundStyle(CT.fgPrimary.opacity(0.5))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 60)
    }
}
