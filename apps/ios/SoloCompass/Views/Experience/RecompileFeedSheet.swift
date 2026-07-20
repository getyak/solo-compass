import SwiftUI

/// Live feed for the deep cross-compile agent loop.
///
/// Before this existed, tapping "deep cross-compile" swapped the ··· glyph for a
/// spinner and ran the whole multi-provider enrichment loop behind it — a tap
/// that found nothing looked identical to one still working, and the failure
/// modes (no AI key, no matching venue, quality downgrade) all resolved to a
/// silent no-op. This sheet appears the instant the user taps, then streams each
/// stage of the loop as it resolves: which source is queried, how many signals
/// it returned, and a green ✓ / muted dash / red ✗ per stage. The terminal card
/// states plainly whether the place was upgraded and why.
struct RecompileFeedSheet: View {
    /// The live feed. `@Bindable` so appended events re-render the list.
    @Bindable var store: RecompileProgressStore
    let onClose: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 10) {
                        header
                        ForEach(store.events) { event in
                            FeedRow(event: event)
                                .id(event.id)
                        }
                        if store.isRunning {
                            runningTail
                        } else {
                            terminalCard
                        }
                    }
                    .padding(.horizontal, 18)
                    .padding(.vertical, 16)
                }
                .background(CT.pageAdaptive.ignoresSafeArea())
                // Follow the tail as new stages stream in.
                .onChange(of: store.events.count) { _, _ in
                    guard let last = store.events.last else { return }
                    withAnimation(.easeOut(duration: 0.25)) {
                        proxy.scrollTo(last.id, anchor: .bottom)
                    }
                }
            }
            .navigationTitle(Text(NSLocalizedString("recompile.feed.title", comment: "Deep cross-compile sheet title")))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(action: onClose) {
                        Text(NSLocalizedString(
                            store.isRunning ? "action.hide" : "action.done",
                            comment: "Dismiss the cross-compile feed"
                        ))
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 7) {
                Image(systemName: "sparkle.magnifyingglass")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(CT.accent)
                Text(store.placeName)
                    .font(.headline)
                    .foregroundStyle(CT.textPrimaryAdaptive)
                    .lineLimit(1)
            }
            Text(NSLocalizedString("recompile.feed.subtitle", comment: "Cross-referencing multiple sources"))
                .font(.caption)
                .foregroundStyle(CT.textMutedAdaptive)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.bottom, 4)
    }

    // MARK: - Running tail

    private var runningTail: some View {
        HStack(spacing: 8) {
            ProgressView()
                .controlSize(.small)
            Text(NSLocalizedString("recompile.feed.working", comment: "Still working line"))
                .font(.caption)
                .foregroundStyle(CT.textMutedAdaptive)
        }
        .padding(.top, 2)
        .transition(.opacity)
    }

    // MARK: - Terminal card

    @ViewBuilder
    private var terminalCard: some View {
        if let upgraded = store.didUpgrade {
            HStack(spacing: 10) {
                Image(systemName: upgraded ? "checkmark.seal.fill" : "info.circle.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(upgraded ? CT.verifiedGreen : CT.warningTextStrong)
                Text(NSLocalizedString(
                    upgraded ? "recompile.feed.upgraded" : "recompile.feed.noChange",
                    comment: "Terminal feed card message"
                ))
                .font(.subheadline.weight(.medium))
                .foregroundStyle(CT.textPrimaryAdaptive)
                .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(upgraded ? CT.successSoft : CT.warningSoft)
            )
            .transition(.opacity)
        }
    }
}

/// One line in the feed: an icon reflecting the stage's status, the stage's
/// human label, and any specific detail (a count, a skip reason).
private struct FeedRow: View {
    let event: CompileProgressEvent

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            statusGlyph
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 1) {
                Text(Self.label(for: event.stage))
                    .font(.subheadline)
                    .foregroundStyle(CT.textPrimaryAdaptive)
                if !event.detail.isEmpty {
                    Text(event.detail)
                        .font(.caption)
                        .foregroundStyle(detailTint)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 0)
        }
        .transition(.opacity)
    }

    @ViewBuilder
    private var statusGlyph: some View {
        switch event.status {
        case .running:
            ProgressView().controlSize(.small)
        case .success:
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(CT.verifiedGreen)
        case .skipped:
            Image(systemName: "minus.circle")
                .font(.system(size: 15, weight: .regular))
                .foregroundStyle(CT.fgSubtle)
        case .failure:
            Image(systemName: "xmark.circle.fill")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(CT.bannerError)
        }
    }

    private var detailTint: Color {
        switch event.status {
        case .failure: return CT.bannerError
        case .skipped: return CT.fgSubtle
        default:       return CT.textMutedAdaptive
        }
    }

    /// Human label per stage. The stage supplies the verb; the event's `detail`
    /// carries specifics (counts, reasons).
    static func label(for stage: CompileProgressEvent.Stage) -> String {
        let key: String
        switch stage {
        case .start:      key = "recompile.stage.start"
        case .amap:       key = "recompile.stage.amap"
        case .mapKit:     key = "recompile.stage.mapKit"
        case .overpass:   key = "recompile.stage.overpass"
        case .foursquare: key = "recompile.stage.foursquare"
        case .ranking:    key = "recompile.stage.ranking"
        case .address:    key = "recompile.stage.address"
        case .synthesis:  key = "recompile.stage.synthesis"
        case .webVerify:  key = "recompile.stage.webVerify"
        case .adopt:      key = "recompile.stage.adopt"
        case .done:       key = "recompile.stage.done"
        case .failed:     key = "recompile.stage.failed"
        }
        return NSLocalizedString(key, comment: "Cross-compile stage label")
    }
}
