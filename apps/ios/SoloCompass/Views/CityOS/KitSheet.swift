import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

/// City OS v2 · 落地包 · 万象 landing-kit sheet (PRD §5.2). Four curated
/// essentials (联网 / 钱 / 签证税务 / 安全), each a warm card carrying its main
/// copy, a 独行透镜 one-liner, a freshness dot, and — where it earns it — a
/// deep-link pill, self-computed visa/183-day digits, or dialable emergency
/// numbers. Everything the traveler needs the moment they land, offline-usable.
struct KitSheet: View {
    let kit: [CityKitItem]
    @Bindable var preferences: UserPreferences
    let complianceService: ComplianceService
    /// When set (e.g. opened from the compliance banner), the visa row is
    /// highlighted and scrolled to on appear.
    var focusKind: CityKitItem.Kind?
    /// City OS v3 · Plan mode turns the kit into a pre-trip checklist: the
    /// title flips to 「行前清单」 and every row grows a tick circle. The tick
    /// state lives in `CityOSStore` (per city); the closures keep this view
    /// decoupled from the store.
    var planMode: Bool = false
    var isTodoDone: (CityKitItem.Kind) -> Bool = { _ in false }
    var onToggleTodo: (CityKitItem.Kind) -> Void = { _ in }
    /// City OS v3 · the traveler's current lifecycle stage in this city
    /// (抵达 → 立足 → 生活 → 回顾). When set (Live mode with an entry date), the
    /// sheet grows a stage banner up top and floats the stage's most relevant
    /// row (SIM on 抵达, visa on 立足/生活) to the front — the same "生存 OS"
    /// framing a digital nomad thinks in. Nil (Plan / no entry date) keeps the
    /// static net → money → visa → safety order and hides the banner.
    var stage: CityStage? = nil
    let onDismiss: () -> Void

    @Environment(\.colorScheme) private var colorScheme
    /// A lightweight in-sheet toast for the "已为你打开 … · 回来继续" deep-link cue.
    @State private var toast: String?

    /// Kit rows ordered net → money → visa → safety regardless of server order,
    /// so the sheet's shape is stable. When a lifecycle `stage` is set, the
    /// stage's most relevant row (see `Self.priorityKind`) is floated to the
    /// front so the nomad sees "what matters now" first — the rest keep their
    /// canonical relative order.
    private var orderedKit: [CityKitItem] {
        let baseRank: [CityKitItem.Kind: Int] = [.net: 0, .money: 1, .visa: 2, .safety: 3]
        let priority = stage.flatMap(Self.priorityKind)
        return kit.sorted { lhs, rhs in
            // Stage-priority row wins outright; ties fall back to canonical order.
            if let priority {
                if lhs.kind == priority && rhs.kind != priority { return true }
                if rhs.kind == priority && lhs.kind != priority { return false }
            }
            return (baseRank[lhs.kind] ?? 9) < (baseRank[rhs.kind] ?? 9)
        }
    }

    /// The kit row a given lifecycle stage most wants front-and-centre. 抵达 →
    /// connectivity (get a SIM, get online); 立足 & 生活 → visa (days left, the
    /// 183-day tax line, renew-or-move decision — the nomad's steady anxiety);
    /// 回顾 has no operational priority, so the static order stands.
    static func priorityKind(for stage: CityStage) -> CityKitItem.Kind? {
        switch stage {
        case .land:            return .net
        case .settle, .live:   return .visa
        case .leave:           return nil
        }
    }

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: 12) {
                        if let stage, !planMode, let line = Self.stagePrompt(for: stage) {
                            stageBanner(stage: stage, prompt: line)
                        }
                        ForEach(orderedKit) { item in
                            KitRowCard(
                                item: item,
                                preferences: preferences,
                                complianceService: complianceService,
                                isFocused: item.kind == focusKind,
                                planTick: planMode ? isTodoDone(item.kind) : nil,
                                onToggleTick: { onToggleTodo(item.kind) },
                                onOpenLink: openLink
                            )
                            .id(item.kind)
                        }
                    }
                    .padding(16)
                }
                .background(groupBackground.ignoresSafeArea())
                .onAppear {
                    guard let focusKind else { return }
                    withAnimation(.easeInOut(duration: 0.35)) {
                        proxy.scrollTo(focusKind, anchor: .center)
                    }
                }
            }
            .navigationTitle(planMode
                ? NSLocalizedString("cityos.kit.title.plan", comment: "行前清单 sheet title")
                : NSLocalizedString("cityos.kit.title", comment: "落地包 sheet title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(NSLocalizedString("common.done", comment: "Done")) { onDismiss() }
                }
            }
            .overlay(alignment: .bottom) { toastOverlay }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }

    private var groupBackground: Color {
        colorScheme == .dark ? CT.warmSheetDark : CT.surfaceSunken
    }

    // MARK: - Stage banner (v3 · 生存 OS framing)

    /// One localized, action-first line per stage — what a nomad should do *now*.
    /// 回顾 returns nil (no operational nudge once you're leaving).
    static func stagePrompt(for stage: CityStage) -> String? {
        switch stage {
        case .land:
            return NSLocalizedString("cityos.kit.stage.land.prompt", comment: "抵达 stage nudge — get connected")
        case .settle:
            return NSLocalizedString("cityos.kit.stage.settle.prompt", comment: "立足 stage nudge — visa + base")
        case .live:
            return NSLocalizedString("cityos.kit.stage.live.prompt", comment: "生活 stage nudge — tax line + rhythm")
        case .leave:
            return nil
        }
    }

    /// The stage banner: a warm accent strip carrying the stage label + its
    /// action line. Mirrors the lens-line idiom (sparkle + accentSoft) so it
    /// reads as part of the sheet, not a foreign alert.
    private func stageBanner(stage: CityStage, prompt: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "location.north.line.fill")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(CT.accent)
                .frame(width: 30, height: 30)
                .background(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(colorScheme == .dark ? CT.warmSunkenDark : CT.accentSoft)
                )
            VStack(alignment: .leading, spacing: 3) {
                Text(stage.localizedLabel)
                    .font(CT.display(14, .bold))
                    .foregroundStyle(colorScheme == .dark ? CT.fgPrimaryDark : CT.fgPrimary)
                Text(prompt)
                    .font(CT.body(12.5, .medium))
                    .foregroundStyle(CT.accent)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(colorScheme == .dark ? CT.warmSunkenDark : CT.accentSoft)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text("\(stage.localizedLabel): \(prompt)"))
    }

    // MARK: - Deep link + toast

    private func openLink(_ url: URL, label: String) {
        #if canImport(UIKit)
        UIApplication.shared.open(url)
        #endif
        let text = String(
            format: NSLocalizedString("cityos.kit.link.toast", comment: "已为你打开 %@ · 回来继续"),
            label
        )
        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) { toast = text }
        Task {
            try? await Task.sleep(for: .seconds(2.4))
            withAnimation(.easeInOut(duration: 0.3)) { toast = nil }
        }
    }

    @ViewBuilder
    private var toastOverlay: some View {
        if let toast {
            Text(toast)
                .font(CT.body(13, .medium))
                .foregroundStyle(.white)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(Capsule().fill(CT.accent))
                .padding(.bottom, 24)
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .accessibilityAddTraits(.updatesFrequently)
        }
    }
}

// MARK: - KitRowCard

/// One landing-kit row. Common chrome (icon tile, title, main copy, lens line,
/// freshness footer) plus a kind-specific trailer: deep-link pill (net/money),
/// visa/183-day self-computation (visa), or dialable numbers (safety).
private struct KitRowCard: View {
    let item: CityKitItem
    @Bindable var preferences: UserPreferences
    let complianceService: ComplianceService
    let isFocused: Bool
    /// Non-nil in Plan mode: the row's pre-trip tick state (v3 行前清单).
    var planTick: Bool?
    var onToggleTick: () -> Void = {}
    let onOpenLink: (URL, String) -> Void

    @Environment(\.colorScheme) private var colorScheme

    private var health: HealthStatus {
        CityBriefHealth.health(lastVerifiedAt: item.lastVerifiedAt, serverHealth: item.serverHealth)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            Text(item.main)
                .font(CT.body(14))
                .foregroundStyle(primaryText)
                .fixedSize(horizontal: false, vertical: true)
            if let lens = item.lens, !lens.isEmpty {
                lensLine(lens)
            }
            trailer
            FreshnessFooter(status: health, lastVerifiedAt: item.lastVerifiedAt)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(cardFill)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(isFocused ? CT.accent : borderColor, lineWidth: isFocused ? 1.5 : 0.5)
        )
        .accessibilityElement(children: .contain)
    }

    private var header: some View {
        HStack(spacing: 11) {
            Image(systemName: item.kind.symbolName)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(CT.accent)
                .frame(width: 34, height: 34)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(iconTileFill)
                )
            Text(item.name)
                .font(CT.display(15, .bold))
                .foregroundStyle(primaryText)
            Spacer(minLength: 0)
            if let planTick {
                tickCircle(on: planTick)
            }
        }
    }

    /// Plan-mode pre-trip tick: empty circle → verifiedGreen filled check.
    private func tickCircle(on: Bool) -> some View {
        Button {
            Haptics.impact(.light)
            onToggleTick()
        } label: {
            Image(systemName: "checkmark")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(on ? Color.white : Color.clear)
                .frame(width: 26, height: 26)
                .background(
                    Circle().fill(on ? CT.verifiedGreen : Color.clear)
                )
                .overlay(
                    Circle().strokeBorder(
                        on ? CT.verifiedGreen : borderColor,
                        lineWidth: 1.5
                    )
                )
                .contentShape(Circle())
        }
        .buttonStyle(PressableButtonStyle(pressedScale: 0.92))
        .animation(.spring(response: 0.25, dampingFraction: 0.8), value: on)
        .accessibilityLabel(Text(on
            ? NSLocalizedString("cityos.kit.todo.done.a11y", comment: "已备")
            : NSLocalizedString("cityos.kit.todo.pending.a11y", comment: "标记已备")))
        .accessibilityAddTraits(on ? [.isSelected] : [])
    }

    /// The existing hint idiom: sparkle prefix + accentSoft capsule + accent text.
    private func lensLine(_ lens: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Image(systemName: "sparkle")
                .font(.system(size: 10, weight: .semibold))
            Text(lens)
                .font(CT.body(12.5, .medium))
                .fixedSize(horizontal: false, vertical: true)
        }
        .foregroundStyle(CT.accent)
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(lensFill)
        )
    }

    @ViewBuilder
    private var trailer: some View {
        switch item.kind {
        case .visa:
            VisaComplianceControl(preferences: preferences, complianceService: complianceService, kitAction: item.action)
        case .safety:
            if let numbers = item.action?.numbers, !numbers.isEmpty {
                emergencyNumbers(numbers)
            }
            deepLinkPill
        default:
            deepLinkPill
        }
    }

    @ViewBuilder
    private var deepLinkPill: some View {
        if let url = item.linkURL {
            let label = item.linkLabel ?? url.host ?? NSLocalizedString("cityos.kit.link.open", comment: "Open")
            Button {
                Haptics.impact(.light)
                onOpenLink(url, label)
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "arrow.up.forward.app")
                        .font(.system(size: 11, weight: .semibold))
                    Text(label)
                        .font(CT.body(12.5, .semibold))
                }
                .foregroundStyle(CT.accent)
                .padding(.horizontal, 11)
                .padding(.vertical, 6)
                .background(Capsule().fill(lensFill))
            }
            .buttonStyle(PressableButtonStyle(pressedScale: 0.96))
            .accessibilityLabel(Text(String(
                format: NSLocalizedString("cityos.kit.link.open.a11y", comment: "Open %@"),
                label
            )))
        }
    }

    /// Dialable emergency numbers — plain `tel:` links, offline-usable.
    private func emergencyNumbers(_ numbers: [CityKitAction.EmergencyNumber]) -> some View {
        VStack(spacing: 6) {
            ForEach(numbers, id: \.number) { entry in
                if let url = URL(string: "tel:\(entry.number)") {
                    Link(destination: url) {
                        HStack(spacing: 8) {
                            Image(systemName: "phone.fill")
                                .font(.system(size: 12, weight: .semibold))
                            Text(entry.label)
                                .font(CT.body(13, .medium))
                            Spacer(minLength: 0)
                            Text(entry.number)
                                .font(CT.mono(14, .semibold))
                        }
                        .foregroundStyle(CT.accent)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 9)
                        .frame(maxWidth: .infinity)
                        .background(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(lensFill)
                        )
                    }
                    .accessibilityLabel(Text(String(
                        format: NSLocalizedString("cityos.kit.call.a11y", comment: "Call %1$@ at %2$@"),
                        entry.label, entry.number
                    )))
                }
            }
        }
    }

    // MARK: - Colors

    private var cardFill: Color { colorScheme == .dark ? CT.warmCardDark : CT.surfaceWhite }
    private var iconTileFill: Color { colorScheme == .dark ? CT.warmSunkenDark : CT.accentSoft }
    private var lensFill: Color { colorScheme == .dark ? CT.warmSunkenDark : CT.accentSoft }
    private var borderColor: Color { colorScheme == .dark ? CT.warmBorderDark : CT.borderSubtle }
    private var primaryText: Color { colorScheme == .dark ? CT.fgPrimaryDark : CT.fgPrimary }
}

// MARK: - VisaComplianceControl

/// The visa/183-day self-computation trailer. When the traveler has entered
/// their entry date, show the big mono counters + a reminder toggle; otherwise
/// let them set entry date + visa length inline (the only kit input the app
/// stores locally, PRD §5.2).
private struct VisaComplianceControl: View {
    @Bindable var preferences: UserPreferences
    let complianceService: ComplianceService
    let kitAction: CityKitAction?

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        if let state = complianceService.state() {
            counters(state)
        } else {
            entrySetup
        }
    }

    private func counters(_ state: ComplianceService.State) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                counter(
                    value: state.visaDaysRemaining,
                    label: NSLocalizedString("cityos.visa.daysLeft", comment: "剩 N 天签证"),
                    isCritical: state.isCritical
                )
                counter(
                    value: state.taxDaysRemaining,
                    label: NSLocalizedString("cityos.visa.taxLine", comment: "距 183 天税务线 M 天"),
                    isCritical: false
                )
            }
            Toggle(isOn: $preferences.visaReminderEnabled) {
                Text(NSLocalizedString("cityos.visa.reminder.toggle", comment: "到期提醒"))
                    .font(CT.body(13, .medium))
                    .foregroundStyle(primaryText)
            }
            .tint(CT.accent)
            .onChange(of: preferences.visaReminderEnabled) { _, _ in
                Task { await complianceService.syncVisaReminder() }
            }
        }
    }

    private func counter(value: Int, label: String, isCritical: Bool) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("\(value)")
                .font(CT.mono(26, .bold))
                .foregroundStyle(isCritical ? CT.warningText : CT.accent)
                .contentTransition(.numericText())
            Text(label)
                .font(CT.body(10.5))
                .foregroundStyle(CT.fgMuted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text("\(label): \(value)"))
    }

    private var entrySetup: some View {
        VStack(alignment: .leading, spacing: 10) {
            DatePicker(
                NSLocalizedString("cityos.visa.entryDate", comment: "入境日期"),
                selection: entryDateBinding,
                displayedComponents: .date
            )
            .font(CT.body(13, .medium))
            Stepper(
                value: visaLengthBinding,
                in: 1...365
            ) {
                Text(String(
                    format: NSLocalizedString("cityos.visa.length", comment: "签证 N 天"),
                    visaLengthBinding.wrappedValue
                ))
                .font(CT.body(13, .medium))
                .foregroundStyle(primaryText)
            }
        }
    }

    /// Setting an entry date flips the row to counter mode (state becomes
    /// non-nil once both entry date and length are stored).
    private var entryDateBinding: Binding<Date> {
        Binding(
            get: { preferences.visaEntryDate ?? Date() },
            set: { newValue in
                preferences.visaEntryDate = newValue
                if preferences.visaLengthDays == nil {
                    preferences.visaLengthDays = kitAction?.visaDays ?? 30
                }
            }
        )
    }

    private var visaLengthBinding: Binding<Int> {
        Binding(
            get: { preferences.visaLengthDays ?? kitAction?.visaDays ?? 30 },
            set: { preferences.visaLengthDays = $0 }
        )
    }

    private var primaryText: Color { colorScheme == .dark ? CT.fgPrimaryDark : CT.fgPrimary }
}
