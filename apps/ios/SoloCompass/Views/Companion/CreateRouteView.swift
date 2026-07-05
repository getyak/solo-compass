import SwiftUI
import CoreLocation

// MARK: - CreateRouteEntryCard

/// Dashed entry card shown beneath the routes section in the bottom sheet:
/// "創建你自己的路線 · 串聯幾個地點 · 可選擇招募同伴一起走". Tapping it opens
/// `CreateRouteView`. Mirrors the reference design's create-route affordance.
struct CreateRouteEntryCard: View {
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(CT.accent)
                        .frame(width: 44, height: 44)
                    Image(systemName: "plus")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(.white)
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text(NSLocalizedString("route.create.entry.title", comment: "Create your own route"))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(CT.fgPrimary)
                    Text(NSLocalizedString("route.create.entry.subtitle", comment: "Link a few stops · optionally recruit companions"))
                        .font(.caption)
                        .foregroundStyle(CT.fgMuted)
                        .lineLimit(2)
                }
                Spacer(minLength: 4)
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(CT.fgSubtle)
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(CT.surfaceWhite)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(
                        CT.borderDefault,
                        style: StrokeStyle(lineWidth: 1, dash: [5, 4])
                    )
            )
        }
        // PressableButtonStyle drives the press-scale via the system's own tap
        // recognizer. The previous `.simultaneousGesture(DragGesture(minimumDistance: 0))`
        // press-feedback hack swallowed the tap inside the BottomInfoSheet's
        // ScrollView — a zero-distance drag claims the touch and the host scroll
        // view classifies the release as a drag, so the Button action never fired
        // and the card was un-tappable. See [[project_dead_fab_sheet_wiring]] kin.
        .buttonStyle(PressableButtonStyle(pressedScale: 0.985))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text(NSLocalizedString("route.create.entry.title", comment: "Create your own route")))
        .accessibilityHint(Text(NSLocalizedString("route.create.entry.subtitle", comment: "Create route hint")))
    }
}

// MARK: - CreateRouteView

/// Build a route by selecting a few nearby experiences — either by hand or by
/// letting the AI string them into a walk — then save it as a `userCreated`
/// (or `coCreated` when AI-seeded) route. Companion recruiting is offered as a
/// follow-up from the saved route's detail, so this flow stays focused on the
/// walk itself.
struct CreateRouteView: View {
    /// Nearby experiences the user can pick stops from.
    let candidates: [Experience]
    let cityCode: String
    let userCoordinate: CLLocationCoordinate2D?
    /// Called with the saved route so the caller can persist + refresh.
    let onSave: (Route) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(AIService.self) private var aiService

    @State private var selectedIds: [String] = []
    @State private var title: String = ""
    @State private var pace: Pace = .relaxed
    @State private var isGenerating = false
    @State private var aiSummary: String?

    /// Selected experiences in selection order (the walk order).
    private var orderedSelection: [Experience] {
        selectedIds.compactMap { id in candidates.first { $0.id == id } }
    }

    private var canSave: Bool { selectedIds.count >= 2 }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    aiGenerateButton
                    summaryHeader
                    titleField
                    pacePicker
                    pickerSection
                }
                .padding(16)
            }
            .background(CT.bgWarm)
            .navigationTitle(NSLocalizedString("route.create.title", comment: "Create route nav title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(NSLocalizedString("action.cancel", comment: "Cancel")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(NSLocalizedString("route.create.save", comment: "Save route")) { save() }
                        .disabled(!canSave)
                        .fontWeight(.semibold)
                }
            }
        }
    }

    // MARK: - Sections

    private var aiGenerateButton: some View {
        Button { Task { await generate() } } label: {
            HStack(spacing: 8) {
                if isGenerating {
                    ProgressView().tint(CT.accent)
                } else {
                    Image(systemName: "sparkles")
                        .font(.system(size: 14, weight: .semibold))
                }
                Text(NSLocalizedString("route.create.ai", comment: "Let AI build the route"))
                    .font(.subheadline.weight(.semibold))
            }
            .foregroundStyle(CT.sunGoldDeep)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous).fill(CT.sunGoldSoft)
            )
        }
        .buttonStyle(.plain)
        .disabled(isGenerating || candidates.count < 2)
    }

    @ViewBuilder
    private var summaryHeader: some View {
        if let aiSummary, !aiSummary.isEmpty {
            HStack(spacing: 6) {
                Image(systemName: "sparkles").font(.system(size: 11, weight: .semibold))
                Text(aiSummary).font(.caption).fixedSize(horizontal: false, vertical: true)
            }
            .foregroundStyle(CT.sunGoldDeep)
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(CT.sunGoldSoft))
        }
    }

    private var titleField: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(NSLocalizedString("route.create.titleLabel", comment: "Route title field label"))
                .font(.caption.weight(.semibold))
                .foregroundStyle(CT.fgMuted)
            TextField(
                NSLocalizedString("route.create.titlePlaceholder", comment: "Route title placeholder"),
                text: $title
            )
            .textFieldStyle(.plain)
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(CT.surfaceWhite))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(CT.borderSubtle, lineWidth: 0.5))
        }
    }

    private var pacePicker: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(NSLocalizedString("route.create.paceLabel", comment: "Pace field label"))
                .font(.caption.weight(.semibold))
                .foregroundStyle(CT.fgMuted)
            Picker("", selection: $pace) {
                ForEach(Pace.allCases, id: \.self) { p in
                    Text(p.localizedLabel).tag(p)
                }
            }
            .pickerStyle(.segmented)
        }
    }

    private var pickerSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(NSLocalizedString("route.create.pickLabel", comment: "Pick stops label"))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(CT.fgMuted)
                Spacer()
                Text(String(
                    format: NSLocalizedString("route.create.selectedCount", comment: "N selected"),
                    selectedIds.count
                ))
                .font(.caption2.monospacedDigit())
                .foregroundStyle(CT.fgSubtle)
            }
            ForEach(candidates) { exp in
                selectRow(exp)
            }
        }
    }

    private func selectRow(_ exp: Experience) -> some View {
        let order = selectedIds.firstIndex(of: exp.id)
        let isSelected = order != nil
        return Button { toggle(exp.id) } label: {
            HStack(spacing: 12) {
                ZStack {
                    Circle().fill(exp.category.color).frame(width: 34, height: 34)
                    if let order {
                        Text("\(order + 1)")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(.white)
                    } else {
                        Image(systemName: exp.category.symbol)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(.white)
                    }
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(exp.title).font(.subheadline.weight(.medium))
                        .foregroundStyle(CT.fgPrimary).lineLimit(1)
                    Text(String(format: NSLocalizedString("nearby.chip.solo", comment: "Solo score"), exp.soloScore.overall))
                        .font(.caption2.weight(.semibold)).foregroundStyle(CT.verifiedGreen)
                }
                Spacer(minLength: 4)
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 20))
                    .foregroundStyle(isSelected ? CT.accent : CT.fgSubtle)
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(isSelected ? CT.accentSoft : CT.surfaceWhite)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(isSelected ? CT.accentBorder : CT.borderSubtle, lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text(exp.title))
        .accessibilityAddTraits(isSelected ? [.isSelected, .isButton] : .isButton)
    }

    // MARK: - Actions

    private func toggle(_ id: String) {
        #if canImport(UIKit)
        Haptics.selection()
        #endif
        if let idx = selectedIds.firstIndex(of: id) {
            selectedIds.remove(at: idx)
        } else {
            selectedIds.append(id)
        }
    }

    private func generate() async {
        isGenerating = true
        defer { isGenerating = false }
        guard let route = try? await aiService.generateRoute(
            from: candidates,
            cityCode: cityCode,
            userCoordinate: userCoordinate
        ) else { return }
        // Adopt the AI's ordering + copy as the editable starting point.
        selectedIds = route.experienceIds
        if title.isEmpty { title = route.title }
        aiSummary = route.summary
        pace = route.pace
    }

    private func save() {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let finalTitle = trimmed.isEmpty
            ? NSLocalizedString("route.generate.fallback.title", comment: "Default route title")
            : trimmed
        let route = RouteBuilder.makeRoute(
            id: RouteId(rawValue: "user-\(UUID().uuidString.prefix(8))"),
            title: finalTitle,
            summary: aiSummary ?? "",
            orderedExperiences: orderedSelection,
            cityCode: cityCode,
            pace: pace,
            source: aiSummary == nil ? .userCreated : .coCreated,
            // A hand-built route is for *today*: anchor it to the current hour
            // so the Now shelf's `isBestNow()` filter shows it immediately
            // instead of silently hiding the route the user just made.
            bestStartHour: Double(Calendar.current.component(.hour, from: Date()))
        )
        onSave(route)
        // No dismiss() here: the presenting map swaps this sheet's content
        // from .create to .detail in place, and dismissing would tear that
        // detail view down before the user ever sees the saved route.
    }
}
