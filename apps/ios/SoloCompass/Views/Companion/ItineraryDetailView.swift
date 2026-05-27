import SwiftUI

/// Detail view for a single itinerary.
/// Shows all fields: title, city, dates, note, companion toggle, and pinned experiences.
public struct ItineraryDetailView: View {
    let itinerary: Itinerary

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .long
        f.timeStyle = .none
        return f
    }()

    private var formattedStart: String {
        guard let d = iso8601Date(itinerary.startDate) else { return itinerary.startDate }
        return Self.dateFormatter.string(from: d)
    }

    private var formattedEnd: String {
        guard let d = iso8601Date(itinerary.endDate) else { return itinerary.endDate }
        return Self.dateFormatter.string(from: d)
    }

    public var body: some View {
        List {
            // MARK: Header section
            Section {
                LabeledDetailRow(
                    label: NSLocalizedString("itinerary.detail.city", comment: "City label"),
                    value: itinerary.cityCode
                )
                LabeledDetailRow(
                    label: NSLocalizedString("itinerary.detail.startDate", comment: "Start date label"),
                    value: formattedStart
                )
                LabeledDetailRow(
                    label: NSLocalizedString("itinerary.detail.endDate", comment: "End date label"),
                    value: formattedEnd
                )
            }

            // MARK: Note section
            if let note = itinerary.note, !note.isEmpty {
                Section(NSLocalizedString("itinerary.detail.note.header", comment: "Notes section header")) {
                    Text(note)
                        .font(.body)
                        .foregroundStyle(.primary)
                }
            }

            // MARK: Companion section
            Section(NSLocalizedString("itinerary.detail.companion.header", comment: "Companions section header")) {
                HStack {
                    Image(systemName: itinerary.openToCompanions ? "person.2.fill" : "person.fill")
                        .foregroundStyle(itinerary.openToCompanions ? Color.accentColor : .secondary)
                        .frame(width: 24)
                    Text(
                        itinerary.openToCompanions
                        ? NSLocalizedString("itinerary.detail.companion.open", comment: "Open to companions")
                        : NSLocalizedString("itinerary.detail.companion.solo", comment: "Going solo")
                    )
                    .font(.body)
                    .foregroundStyle(.primary)
                }
            }

            // MARK: Experiences section
            Section {
                if itinerary.experienceIds.isEmpty {
                    Text(NSLocalizedString("itinerary.detail.experiences.empty", comment: "No experiences pinned yet"))
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .italic()
                } else {
                    ForEach(itinerary.experienceIds, id: \.self) { expId in
                        HStack(spacing: 8) {
                            Image(systemName: "mappin.circle.fill")
                                .foregroundStyle(Color.accentColor)
                            Text(expId)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                }
            } header: {
                Text(String(
                    format: NSLocalizedString("itinerary.detail.experiences.header", comment: "Experiences header with count"),
                    itinerary.experienceIds.count
                ))
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(itinerary.title)
        .navigationBarTitleDisplayMode(.large)
    }
}

// MARK: - Subviews

private struct LabeledDetailRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.primary)
                .multilineTextAlignment(.trailing)
        }
    }
}

// MARK: - Helpers

private func iso8601Date(_ string: String) -> Date? {
    let f = DateFormatter()
    f.dateFormat = "yyyy-MM-dd"
    f.timeZone = TimeZone(identifier: "UTC")
    return f.date(from: string)
}

// MARK: - Preview

#Preview("With note and experiences") {
    NavigationStack {
        ItineraryDetailView(itinerary: .sample)
    }
}

#Preview("Open to companions, no experiences") {
    NavigationStack {
        ItineraryDetailView(itinerary: Itinerary(
            id: ItineraryId(rawValue: "itin_preview_b"),
            ownerId: "user_preview",
            title: "Bali Retreat",
            cityCode: "DPS",
            startDate: "2026-06-10",
            endDate: "2026-06-20",
            experienceIds: [],
            note: nil,
            openToCompanions: true,
            createdAt: "2026-03-01T09:00:00Z",
            updatedAt: "2026-03-01T09:00:00Z"
        ))
    }
}
