import SwiftUI

/// US-039 — Host converts a private itinerary into a recruiting route.
///
/// Presented from ItineraryDetailView. On submit, builds a Route via
/// Route(itinerary:) from US-005, attaches a RouteCompanion with the form
/// values (status = .open, hostId = deviceId, confirmedMembers = [deviceId]),
/// and persists via RouteStore.save.
public struct OpenForCompanionsSheet: View {
    let itinerary: Itinerary

    @Environment(\.dismiss) private var dismiss

    // MARK: - Form state

    @State private var departureFrom: Date
    @State private var departureTo: Date
    @State private var departureTime: Date
    @State private var pace: Pace = .standard
    @State private var maxMembers: Int = 4
    @State private var visibility: RouteCompanionVisibility = .public
    @State private var hostMessage: String = ""

    @State private var submitted = false

    private let storeProvider: () -> RouteStore

    public init(
        itinerary: Itinerary,
        storeProvider: @escaping () -> RouteStore = { RouteStore() }
    ) {
        self.itinerary = itinerary
        self.storeProvider = storeProvider

        // Default departure window to the itinerary's own dates.
        let from = Self.parseDate(itinerary.startDate) ?? Date()
        let to = Self.parseDate(itinerary.endDate) ?? from.addingTimeInterval(86400 * 3)
        _departureFrom = State(initialValue: from)
        _departureTo = State(initialValue: max(from, to))
        // Default departure time: 09:00 on the from date.
        var comps = Calendar.current.dateComponents([.year, .month, .day], from: from)
        comps.hour = 9; comps.minute = 0
        _departureTime = State(initialValue: Calendar.current.date(from: comps) ?? from)
    }

    // MARK: - Body

    public var body: some View {
        NavigationStack {
            Form {
                departureDateSection
                paceSection
                membersSection
                visibilitySection
                hostMessageSection
            }
            .navigationTitle(NSLocalizedString(
                "openForCompanions.sheet.title",
                comment: "Open For Companions sheet nav title"
            ))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(NSLocalizedString("action.cancel", comment: "Cancel")) {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(NSLocalizedString(
                        "openForCompanions.submit",
                        comment: "Submit button: create recruiting route"
                    )) {
                        submit()
                    }
                    .fontWeight(.semibold)
                    .disabled(submitted)
                }
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        // Protect an edited recruiting form (host message typed, or any default
        // pace/size/visibility changed) from a stray swipe-down.
        .interactiveDismissDisabled(
            !hostMessage.trimmingCharacters(in: .whitespaces).isEmpty
                || pace != .standard
                || maxMembers != 4
                || visibility != .public
        )
    }

    // MARK: - Sections

    private var departureDateSection: some View {
        Section {
            DatePicker(
                NSLocalizedString("openForCompanions.departureFrom", comment: "Departure window start label"),
                selection: $departureFrom,
                displayedComponents: .date
            )
            .onChange(of: departureFrom) { _, newFrom in
                if departureTo < newFrom { departureTo = newFrom }
            }
            DatePicker(
                NSLocalizedString("openForCompanions.departureTo", comment: "Departure window end label"),
                selection: $departureTo,
                in: departureFrom...,
                displayedComponents: .date
            )
            DatePicker(
                NSLocalizedString("openForCompanions.departureTime", comment: "Departure time label"),
                selection: $departureTime,
                displayedComponents: .hourAndMinute
            )
        } header: {
            Text(NSLocalizedString("openForCompanions.departure.header", comment: "Departure section header"))
        }
    }

    private var paceSection: some View {
        Section {
            Picker(
                NSLocalizedString("openForCompanions.pace", comment: "Pace picker label"),
                selection: $pace
            ) {
                ForEach(Pace.allCases, id: \.self) { p in
                    Text(p.localizedLabel).tag(p)
                }
            }
            .pickerStyle(.segmented)
        } header: {
            Text(NSLocalizedString("openForCompanions.pace", comment: "Pace section header"))
        }
    }

    private var membersSection: some View {
        Section {
            Stepper(
                String(format: NSLocalizedString(
                    "openForCompanions.maxMembers.value",
                    comment: "Max members stepper value; %d = count"
                ), maxMembers),
                value: $maxMembers,
                in: 2...8
            )
        } header: {
            Text(NSLocalizedString("openForCompanions.maxMembers", comment: "Max members section header"))
        }
    }

    private var visibilitySection: some View {
        Section {
            Picker(
                NSLocalizedString("openForCompanions.visibility", comment: "Visibility picker label"),
                selection: $visibility
            ) {
                Text(NSLocalizedString("openForCompanions.visibility.public", comment: "Public visibility option"))
                    .tag(RouteCompanionVisibility.public)
                Text(NSLocalizedString("openForCompanions.visibility.linkOnly", comment: "Link-only visibility option"))
                    .tag(RouteCompanionVisibility.linkOnly)
            }
            .pickerStyle(.segmented)
        } header: {
            Text(NSLocalizedString("openForCompanions.visibility", comment: "Visibility section header"))
        }
    }

    private var hostMessageSection: some View {
        Section {
            TextField(
                NSLocalizedString("openForCompanions.hostMessage.placeholder", comment: "Host message placeholder"),
                text: $hostMessage,
                axis: .vertical
            )
            .lineLimit(3...6)
            .onChange(of: hostMessage) { _, new in
                if new.count > 300 { hostMessage = String(new.prefix(300)) }
            }
        } header: {
            Text(NSLocalizedString("openForCompanions.hostMessage", comment: "Host message section header"))
        }
    }

    // MARK: - Submit

    private func submit() {
        submitted = true
        let deviceId = DeviceIdentityService.shared.deviceID

        let timeFmt = DateFormatter()
        timeFmt.dateFormat = "HH:mm"
        let timeString = timeFmt.string(from: departureTime)

        let dateFmt = DateFormatter()
        dateFmt.dateFormat = "yyyy-MM-dd"

        let window = DepartureWindow(
            startDate: dateFmt.string(from: departureFrom),
            to: dateFmt.string(from: departureTo),
            time: timeString
        )

        let companion = RouteCompanion(
            status: .open,
            hostId: deviceId,
            departureWindow: window,
            departureLabel: "\(dateFmt.string(from: departureFrom)) \(timeString)",
            pacePreference: pace.asPacePreference,
            maxMembers: maxMembers,
            confirmedMembers: [deviceId],
            joinRequests: [],
            visibility: visibility,
            groupConversationId: nil,
            hostMessage: hostMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? nil
                : hostMessage.trimmingCharacters(in: .whitespacesAndNewlines)
        )

        var route = Route(itinerary: itinerary)
        route = Route(
            id: route.id,
            title: route.title,
            summary: route.summary,
            experienceIds: route.experienceIds,
            cityCode: route.cityCode,
            region: route.region,
            estimatedDuration: route.estimatedDuration,
            distanceMeters: route.distanceMeters,
            pace: pace,
            tags: route.tags,
            source: .userCreated,
            authorId: deviceId,
            bestStartHour: route.bestStartHour,
            bestNow: route.bestNow,
            verification: route.verification,
            companion: companion
        )

        storeProvider().save(route)
        Haptics.notify(.success)
        dismiss()
    }

    // MARK: - Helpers

    private static func parseDate(_ iso: String) -> Date? {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.timeZone = TimeZone(identifier: "UTC")
        return f.date(from: iso)
    }
}

// MARK: - Pace helpers

private extension Pace {
    var asPacePreference: PacePreference {
        switch self {
        case .relaxed:  return .relaxed
        case .standard: return .standard
        case .packed:   return .packed
        }
    }
}

// MARK: - Preview

#Preview {
    OpenForCompanionsSheet(itinerary: Itinerary(
        id: ItineraryId(rawValue: "itin_preview"),
        ownerId: "user_preview",
        title: "Tokyo Spring 2026",
        cityCode: "TYO",
        startDate: "2026-04-01",
        endDate: "2026-04-10",
        experienceIds: ["exp_cmi_suan_dok_sunset"],
        note: "Focus on cherry blossom spots.",
        openToCompanions: false,
        createdAt: "2026-01-15T09:00:00Z",
        updatedAt: "2026-01-15T09:00:00Z"
    ))
}
