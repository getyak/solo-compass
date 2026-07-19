import SwiftUI

/// Nomad OS B1-d: the "yesterday's seal" receipt on the Today home (design
/// nomad-os-b1-today-home-20260719 §2 ④).
///
/// Design §2 ④ picks option (a): "yesterday's seal" = a capsule the traveler
/// buried yesterday, read from `CapsuleStore.buriedUnripeCapsules()` filtered to
/// yesterday's `createdAt`. It renders only when such a capsule exists — no
/// empty placeholder occupying the row. Tapping opens the capsule detail flow.
///
/// The richer per-day "seal ritual" model is deliberately left to B2 with the
/// ledger; B1-d reuses the existing TimeCapsule / CapsuleStore as-is (no new
/// persistence).
struct TodaySealReceipt: View {
    /// Called when the receipt is tapped — routes to the capsule detail /
    /// chapter card. Wired by the container in a later slice.
    var onOpen: (TimeCapsule) -> Void = { _ in }

    @State private var yesterdayCapsule: TimeCapsule?

    var body: some View {
        Group {
            if let capsule = yesterdayCapsule {
                Button {
                    onOpen(capsule)
                } label: {
                    HStack(spacing: Space.md) {
                        Image(systemName: "archivebox.fill")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(CT.accent)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(NSLocalizedString(
                                "today.seal.yesterdayTitle",
                                comment: "Yesterday you sealed a moment"
                            ))
                            .ctBody(14, .semibold)
                            .foregroundStyle(CT.textPrimaryAdaptive)
                            Text(sealSubtitle(for: capsule))
                                .ctBody(12)
                                .foregroundStyle(CT.textMutedAdaptive)
                                .lineLimit(1)
                        }
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.right")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(CT.fgSubtle)
                    }
                    .padding(Space.lg)
                    .background(
                        RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                            .fill(CT.cardAdaptive)
                    )
                    .padding(.horizontal, Space.xl)
                }
                .buttonStyle(.plain)
            }
        }
        .task { refresh() }
    }

    /// One-line context: the sealed content type, kept generic since the blob is
    /// opaque here (full render lives in the capsule detail view).
    private func sealSubtitle(for capsule: TimeCapsule) -> String {
        switch capsule.contentType {
        case "photo":
            return NSLocalizedString("today.seal.type.photo", comment: "a photo")
        case "voice":
            return NSLocalizedString("today.seal.type.voice", comment: "a voice note")
        default:
            return NSLocalizedString("today.seal.type.text", comment: "a note")
        }
    }

    private func refresh() {
        yesterdayCapsule = Self.yesterdayCapsule(
            from: CapsuleStore.shared.buriedUnripeCapsules(),
            now: Date()
        )
    }

    /// Pick the most recent still-buried capsule created *yesterday* (local
    /// day). Pure so `TodaySealReceiptTests` can pin the day-boundary logic
    /// without a live store: today's and older capsules are excluded, only
    /// yesterday's qualifies. `nonisolated` — no view state touched.
    nonisolated static func yesterdayCapsule(
        from capsules: [TimeCapsule],
        now: Date,
        calendar: Calendar = Calendar.current
    ) -> TimeCapsule? {
        guard let yesterday = calendar.date(byAdding: .day, value: -1, to: now) else {
            return nil
        }
        let yesterdayStart = calendar.startOfDay(for: yesterday)
        let todayStart = calendar.startOfDay(for: now)
        return capsules
            .filter { $0.createdAt >= yesterdayStart && $0.createdAt < todayStart }
            .max(by: { $0.createdAt < $1.createdAt })
    }
}
