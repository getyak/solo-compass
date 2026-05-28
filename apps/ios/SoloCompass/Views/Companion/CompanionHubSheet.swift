import SwiftUI

/// The single entry point into the Companion feature surface. Presented from
/// `CompassMapView` via a person-icon button next to the city pill.
///
/// Rationale: the app's IA is "map is everything, no tabs, no drawer". A hub
/// sheet keeps the social/itinerary surface from polluting the map while still
/// giving the 5 companion screens (Discover, Inbox, Itineraries, Profile, plus
/// presence toggle) a single, obvious doorway.
@available(*, deprecated, message: "Replaced by Settings -> Companion section per A+A+A. Delete after P2 ships.")
public struct CompanionHubSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(CompanionService.self) private var companionService
    @Environment(PresenceService.self) private var presenceService
    @Environment(UserPreferences.self) private var preferences

    /// Currently selected city (e.g. "TYO"). Passed down to `DiscoverListView`
    /// so the discover query is scoped. Falls back to "" when no city — the
    /// Edge Function returns global results in that case.
    let cityCode: String

    public init(cityCode: String) {
        self.cityCode = cityCode
    }

    public var body: some View {
        NavigationStack {
            List {
                Section {
                    presenceRow
                } footer: {
                    Text(NSLocalizedString(
                        "companion.hub.presence.footer",
                        comment: "Explanation that presence is required for nearby discovery"
                    ))
                }

                Section {
                    NavigationLink {
                        DiscoverListView(cityCode: cityCode)
                    } label: {
                        hubRow(
                            symbol: "person.2.wave.2",
                            tint: .accentColor,
                            title: NSLocalizedString("companion.hub.discover.title", comment: ""),
                            subtitle: NSLocalizedString("companion.hub.discover.subtitle", comment: ""),
                            badge: nil
                        )
                    }

                    NavigationLink {
                        RequestInboxView()
                    } label: {
                        hubRow(
                            symbol: "tray.fill",
                            tint: .orange,
                            title: NSLocalizedString("companion.hub.inbox.title", comment: ""),
                            subtitle: NSLocalizedString("companion.hub.inbox.subtitle", comment: ""),
                            badge: inboxBadge
                        )
                    }
                } header: {
                    Text(NSLocalizedString("companion.hub.section.connect", comment: "Connect section header"))
                }

                Section {
                    NavigationLink {
                        ItineraryListView()
                    } label: {
                        hubRow(
                            symbol: "calendar",
                            tint: .blue,
                            title: NSLocalizedString("companion.hub.itineraries.title", comment: ""),
                            subtitle: NSLocalizedString("companion.hub.itineraries.subtitle", comment: ""),
                            badge: nil
                        )
                    }

                    NavigationLink {
                        CompanionProfileView()
                    } label: {
                        hubRow(
                            symbol: "person.crop.circle",
                            tint: .purple,
                            title: NSLocalizedString("companion.hub.profile.title", comment: ""),
                            subtitle: NSLocalizedString("companion.hub.profile.subtitle", comment: ""),
                            badge: nil
                        )
                    }
                } header: {
                    Text(NSLocalizedString("companion.hub.section.you", comment: "Your stuff section header"))
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle(NSLocalizedString("companion.hub.title", comment: "Companion hub navigation title"))
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(NSLocalizedString("common.close", comment: "Close")) { dismiss() }
                }
            }
        }
        .presentationDetents([.large])
    }

    // MARK: - Subviews

    private var presenceRow: some View {
        Toggle(isOn: presenceBinding) {
            HStack(spacing: 12) {
                Image(systemName: presenceService.isActive ? "dot.radiowaves.left.and.right" : "moon.zzz")
                    .font(.title3)
                    .foregroundStyle(presenceService.isActive ? Color.green : Color.secondary)
                    .frame(width: 28)
                VStack(alignment: .leading, spacing: 2) {
                    Text(NSLocalizedString("companion.hub.presence.title", comment: "Be discoverable"))
                        .font(.body.weight(.medium))
                    Text(presenceService.isActive
                         ? NSLocalizedString("companion.hub.presence.on", comment: "On")
                         : NSLocalizedString("companion.hub.presence.off", comment: "Off"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func hubRow(symbol: String, tint: Color, title: String, subtitle: String, badge: Int?) -> some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(tint.opacity(0.15))
                    .frame(width: 36, height: 36)
                Image(systemName: symbol)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(tint)
            }
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(title).font(.body.weight(.medium))
                    if let badge, badge > 0 {
                        Text("\(badge)")
                            .font(.caption2.weight(.semibold).monospacedDigit())
                            .foregroundStyle(.white)
                            .padding(.horizontal, 6)
                            .frame(minWidth: 18, minHeight: 18)
                            .background(Capsule().fill(Color.red))
                    }
                }
                Text(subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(2)
            }
        }
        .padding(.vertical, 2)
    }

    // MARK: - Bindings

    private var presenceBinding: Binding<Bool> {
        Binding(
            get: { presenceService.isActive },
            set: { newValue in
                Task {
                    if newValue {
                        await presenceService.enable()
                    } else {
                        await presenceService.disable()
                    }
                }
            }
        )
    }

    /// Inbox count badge. Returns nil when there are no pending requests so the
    /// row stays visually quiet for cold-start users.
    private var inboxBadge: Int? {
        let n = companionService.inboxRequests.count
        return n > 0 ? n : nil
    }
}

#if DEBUG
#Preview("Hub") {
    CompanionHubSheet(cityCode: "TYO")
        .environment(CompanionService.shared)
        .environment(PresenceService.shared)
        .environment(UserPreferences())
}
#endif
