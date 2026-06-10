import SwiftUI

// MARK: - Traveler co-build sections (extension on ExperienceDetailView)

/// The "AI + travelers co-write" layer rendered inside the detail page: pending
/// field corrections (amber cards above the prose) and the traveler-notes feed
/// with lightweight quick-add. Kept in an extension so it can use the detail
/// view's @State (notes/corrections/filters/draft) directly while staying in its
/// own file. Everything reads from the optional `travelerNoteStore`; when the
/// store isn't injected (previews/tests) the sections render nothing.
extension ExperienceDetailView {

    // MARK: Data loading

    /// Pull notes + corrections for the current place from the store. Called on
    /// appear and after every mutation. No-op without a store.
    func reloadCoBuild() {
        guard let store = travelerNoteStore else { return }
        let id = viewModel.experience.id
        notes = store.notes(for: id)
        corrections = store.corrections(for: id)
    }

    /// Flash a one-shot toast ("信号 +1 · 数据等级 L2") then auto-dismiss.
    func flashLevelToast(_ text: String) {
        levelToastTask?.cancel()
        levelToast = text
        levelToastTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 2_600_000_000)
            guard !Task.isCancelled else { return }
            withAnimation { levelToast = nil }
        }
    }

    // MARK: Pending corrections

    @ViewBuilder
    var correctionsSection: some View {
        if travelerNoteStore != nil, !corrections.isEmpty {
            VStack(spacing: 10) {
                ForEach(corrections) { correction in
                    correctionCard(correction)
                }
            }
        }
    }

    private func correctionCard(_ c: PlaceCorrection) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 7) {
                Image(systemName: "exclamationmark.circle.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(CT.warningText)
                    .frame(width: 18, height: 18)
                    .background(Circle().fill(CT.warningText.opacity(0.16)))
                Text(NSLocalizedString("correction.heading", comment: "Info may need updating").uppercased())
                    .font(CT.displayRounded(10.5, .bold))
                    .tracking(1.2)
                    .foregroundStyle(CT.warningText)
            }
            VStack(alignment: .leading, spacing: 5) {
                Text(c.field)
                    .font(CT.body(13.5, .medium))
                    .foregroundStyle(CT.fgPrimary)
                HStack(spacing: 6) {
                    Text(c.oldVal)
                        .font(CT.mono(12.5))
                        .strikethrough()
                        .foregroundStyle(CT.fgSubtle)
                    Image(systemName: "arrow.right").font(.system(size: 10)).foregroundStyle(CT.fgSubtle)
                    Text(c.newVal)
                        .font(CT.mono(12.5, .semibold))
                        .foregroundStyle(CT.successText)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(RoundedRectangle(cornerRadius: 4).fill(CT.successSoft))
                }
                Text(c.sourceNote)
                    .font(CT.mono(10.5))
                    .foregroundStyle(CT.fgSubtle)
            }
            HStack(spacing: 7) {
                Button {
                    Haptics.impact(.light)
                    travelerNoteStore?.acceptCorrection(id: c.id)
                    registerContribution(String(
                        format: NSLocalizedString("correction.confirmed.toast", comment: "Confirmed toast"),
                        c.field
                    ))
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark").font(.system(size: 10, weight: .bold))
                        Text(NSLocalizedString("correction.confirm", comment: "Confirm"))
                    }
                    .font(CT.body(12, .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 13).padding(.vertical, 6)
                    .background(Capsule().fill(CT.accent))
                }
                .buttonStyle(.plain)
                Button {
                    Haptics.impact(.light)
                    travelerNoteStore?.dismissCorrection(id: c.id)
                    reloadCoBuild()
                } label: {
                    Text(NSLocalizedString("correction.dismiss", comment: "Inaccurate"))
                        .font(CT.body(12, .semibold))
                        .foregroundStyle(CT.fgPrimary)
                        .padding(.horizontal, 13).padding(.vertical, 6)
                        .background(Capsule().fill(Color.black.opacity(0.04)))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 13).padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 14).fill(CT.warningSoft))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(CT.warningText.opacity(0.22), lineWidth: 0.5))
    }

    // MARK: Notes feed + quick-add

    @ViewBuilder
    var travelerNotesSection: some View {
        if travelerNoteStore != nil {
            VStack(alignment: .leading, spacing: 12) {
                notesHeader
                let filtered = filteredNotes
                if filtered.isEmpty {
                    Text(NSLocalizedString("notes.empty", comment: "No notes of this kind"))
                        .font(CT.body(13))
                        .foregroundStyle(CT.fgSubtle)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 18)
                } else {
                    let shown = notesExpanded ? filtered : Array(filtered.prefix(3))
                    VStack(spacing: 0) {
                        ForEach(Array(shown.enumerated()), id: \.element.id) { index, note in
                            if index > 0 {
                                Rectangle().fill(CT.borderSubtle).frame(height: 0.5)
                            }
                            noteRow(note)
                        }
                    }
                    if filtered.count > 3 {
                        Button {
                            withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2)) {
                                notesExpanded.toggle()
                            }
                        } label: {
                            Text(notesExpanded
                                ? NSLocalizedString("notes.collapse", comment: "Collapse notes")
                                : String(format: NSLocalizedString("notes.expandAll", comment: "Expand all N notes"), filtered.count))
                                .font(CT.body(12, .medium))
                                .foregroundStyle(CT.accent)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.vertical, 9)
                                .overlay(alignment: .top) {
                                    Rectangle().fill(CT.borderSubtle).frame(height: 0.5)
                                }
                        }
                        .buttonStyle(.plain)
                    }
                }
                quickAddPanel
            }
        }
    }

    private var notesHeader: some View {
        HStack(alignment: .firstTextBaseline) {
            HStack(spacing: 6) {
                Text(NSLocalizedString("notes.title", comment: "Traveler notes").uppercased())
                    .font(CT.displayRounded(11, .bold))
                    .tracking(1.6)
                    .foregroundStyle(CT.fgMuted)
                Text("\(notes.count)")
                    .font(CT.mono(10))
                    .foregroundStyle(CT.fgSubtle)
            }
            Spacer()
            // Filter segments — all / experience / correction.
            HStack(spacing: 2) {
                ForEach(NoteFilter.allCases, id: \.self) { filter in
                    Button {
                        Haptics.selection()
                        notesFilter = filter
                    } label: {
                        Text(noteFilterLabel(filter))
                            .font(CT.body(11, notesFilter == filter ? .semibold : .regular))
                            .foregroundStyle(notesFilter == filter ? CT.fgPrimary : CT.fgMuted)
                            .padding(.horizontal, 9).padding(.vertical, 3)
                            .background {
                                if notesFilter == filter {
                                    Capsule().fill(CT.surfaceWhite).shadow(color: .black.opacity(0.06), radius: 1, y: 1)
                                }
                            }
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(2)
            .background(Capsule().fill(CT.surfaceSunken))
        }
    }

    private func noteFilterLabel(_ filter: NoteFilter) -> String {
        switch filter {
        case .all:        return NSLocalizedString("notes.filter.all", comment: "All")
        case .experience: return NSLocalizedString("notes.filter.experience", comment: "Experience")
        case .correction: return NSLocalizedString("notes.filter.correction", comment: "Correction")
        }
    }

    var filteredNotes: [TravelerNote] {
        switch notesFilter {
        case .all:        return notes
        case .experience: return notes.filter { $0.kind == .experience }
        case .correction: return notes.filter { $0.kind == .correction }
        }
    }

    private func noteRow(_ note: TravelerNote) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 8) {
                Text(note.authorInitial)
                    .font(CT.displayRounded(11, .bold))
                    .foregroundStyle(.white)
                    .frame(width: 22, height: 22)
                    .background(Circle().fill(noteAvatarColor(note)))
                HStack(spacing: 6) {
                    Text(note.isMine
                        ? NSLocalizedString("notes.author.you", comment: "You")
                        : String(format: NSLocalizedString("notes.author.traveler", comment: "Traveler X"), note.authorInitial))
                        .font(CT.body(12.5, .medium))
                        .foregroundStyle(CT.fgPrimary)
                    Text((note.kind == .correction
                        ? NSLocalizedString("notes.tag.correction", comment: "Correction")
                        : NSLocalizedString("notes.tag.experience", comment: "Experience")).uppercased())
                        .font(CT.displayRounded(9.5, .bold))
                        .tracking(1.0)
                        .foregroundStyle(note.kind == .correction ? CT.warningText : CT.sunGoldDeep)
                }
                Spacer(minLength: 6)
                Text(relativeTime(note.createdAt))
                    .font(CT.mono(10.5))
                    .foregroundStyle(CT.fgSubtle)
            }
            Text(note.text)
                .font(CT.body(13.5))
                .foregroundStyle(CT.fgPrimary)
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 6) {
                noteStatusBadge(note)
                Spacer(minLength: 0)
                if !note.isMine {
                    let confirmed = confirmedNoteIds.contains(note.id)
                    Button {
                        guard !confirmed else { return }
                        Haptics.impact(.light)
                        confirmedNoteIds.insert(note.id)
                        travelerNoteStore?.confirmNote(id: note.id)
                        registerContribution(NSLocalizedString("notes.contributed.toast", comment: "Thanks toast"))
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: confirmed ? "hand.thumbsup.fill" : "hand.thumbsup")
                                .font(.system(size: 10))
                            Text(confirmed
                                ? NSLocalizedString("notes.confirmed", comment: "Confirmed")
                                : NSLocalizedString("notes.confirm", comment: "Confirm too"))
                        }
                        .font(CT.mono(11))
                        .foregroundStyle(confirmed ? CT.successText : CT.fgMuted)
                        .padding(.horizontal, 9).padding(.vertical, 4)
                        .background(Capsule().fill(confirmed ? CT.successSoft : .clear))
                        .overlay(Capsule().strokeBorder(confirmed ? CT.successText.opacity(0.3) : CT.borderSubtle, lineWidth: 0.5))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(.vertical, 13)
    }

    private func noteAvatarColor(_ note: TravelerNote) -> Color {
        if let hex = note.authorColor, let c = Color(hex: hex) { return c }
        return CT.accent
    }

    @ViewBuilder
    private func noteStatusBadge(_ note: TravelerNote) -> some View {
        if note.aiAdopted {
            noteBadge(icon: "sparkles", text: NSLocalizedString("notes.status.adopted", comment: "AI adopted"),
                      fg: CT.accent, bg: CT.accentSoft, border: CT.accentBorder)
        } else if note.confirms >= 3 {
            noteBadge(icon: "checkmark", text: String(format: NSLocalizedString("notes.status.verified", comment: "Verified by N"), note.confirms),
                      fg: CT.successText, bg: CT.successSoft, border: .clear)
        } else {
            noteBadge(icon: "clock", text: String(format: NSLocalizedString("notes.status.pending", comment: "Pending N"), note.confirms),
                      fg: CT.fgMuted, bg: CT.surfaceSunken, border: .clear)
        }
    }

    private func noteBadge(icon: String, text: String, fg: Color, bg: Color, border: Color) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon).font(.system(size: 9))
            Text(text).font(CT.mono(10.5))
        }
        .foregroundStyle(fg)
        .padding(.horizontal, 8).padding(.vertical, 3)
        .background(Capsule().fill(bg))
        .overlay(Capsule().strokeBorder(border, lineWidth: 0.5))
    }

    // MARK: Quick-add

    private var quickAddPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "pencil").font(.system(size: 11))
                Text(NSLocalizedString("notes.addPrompt", comment: "Leave a note for others").uppercased())
                    .font(CT.displayRounded(10.5, .bold))
                    .tracking(1.2)
                Spacer(minLength: 0)
                Text(NSLocalizedString("notes.addHint", comment: "AI cross-verifies"))
                    .font(CT.mono(9.5))
                    .foregroundStyle(CT.fgSubtle)
                    .textCase(nil)
            }
            .foregroundStyle(CT.fgMuted)

            // Mood chips, category-specific.
            FlowLayout(spacing: 5) {
                ForEach(moodPresets, id: \.self) { mood in
                    let picked = pickedMoods.contains(mood)
                    Button {
                        Haptics.selection()
                        if picked { pickedMoods.remove(mood) } else { pickedMoods.insert(mood) }
                    } label: {
                        Text(mood)
                            .font(CT.body(12))
                            .foregroundStyle(picked ? .white : CT.fgPrimary)
                            .padding(.horizontal, 11).padding(.vertical, 5)
                            .background(Capsule().fill(picked ? CT.accent : CT.surfaceSunken))
                    }
                    .buttonStyle(.plain)
                }
            }

            HStack(spacing: 8) {
                TextField(
                    pickedMoods.isEmpty
                        ? NSLocalizedString("notes.input.placeholder", comment: "e.g. quiet on Tue afternoon")
                        : NSLocalizedString("notes.input.placeholderWithMood", comment: "Add a line (optional)"),
                    text: $noteDraft
                )
                .font(CT.body(13))
                .textFieldStyle(.plain)
                .submitLabel(.send)
                .onSubmit(submitNote)
                Button {
                    submitNote()
                } label: {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(canSubmitNote ? .white : CT.fgSubtle)
                        .frame(width: 30, height: 30)
                        .background(Circle().fill(canSubmitNote ? CT.accent : CT.surfaceSunken))
                }
                .buttonStyle(.plain)
                .disabled(!canSubmitNote)
                .accessibilityLabel(Text(NSLocalizedString("notes.submit", comment: "Submit note")))
            }
            .padding(.top, 10)
            .overlay(alignment: .top) {
                Rectangle().fill(CT.borderSubtle).frame(height: 0.5)
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 13)
        .background(RoundedRectangle(cornerRadius: 14).fill(CT.surfaceWhite))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(CT.borderSubtle, lineWidth: 0.5))
    }

    private var canSubmitNote: Bool {
        !pickedMoods.isEmpty || !noteDraft.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private var moodPresets: [String] {
        ExperienceDetailView.moodPresets(for: viewModel.experience.category)
    }

    private func submitNote() {
        guard canSubmitNote, let store = travelerNoteStore else { return }
        // Compose moods + free text into one line, mirroring the design.
        let moods = pickedMoods.sorted().joined(separator: " · ")
        let text = noteDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        let composed = [moods, text].filter { !$0.isEmpty }.joined(separator: "。")
        let final = composed.hasSuffix("。") || composed.isEmpty ? composed : composed + "。"
        _ = store.addNote(experienceId: viewModel.experience.id, text: final, kind: .experience)
        pickedMoods.removeAll()
        noteDraft = ""
        Haptics.notify(.success)
        registerContribution(NSLocalizedString("notes.contributed.toast", comment: "Thanks toast"))
    }

    /// Mark the user as having contributed, reload, and show the level toast.
    func registerContribution(_ toast: String) {
        let firstTime = !userContributed
        userContributed = true
        reloadCoBuild()
        flashLevelToast(firstTime ? NSLocalizedString("notes.level.up.toast", comment: "Level up toast") : toast)
    }

    /// Relative-time label ("3 天前") from an ISO 8601 string.
    func relativeTime(_ iso: String) -> String {
        guard let date = ISO8601DateFormatter().date(from: iso) else { return "" }
        let fmt = RelativeDateTimeFormatter()
        fmt.unitsStyle = .short
        return fmt.localizedString(for: date, relativeTo: Date())
    }

    // MARK: Mood presets (category-specific)

    /// Category-tuned mood chips for quick-add (mirrors the design MOOD_PRESETS).
    static func moodPresets(for category: ExperienceCategory) -> [String] {
        func keys(_ raw: [String]) -> [String] { raw.map { NSLocalizedString("mood.\($0)", comment: "Mood chip") } }
        switch category {
        case .coffee, .work:
            return keys(["quiet", "slowWifi", "comfySeat", "friendlyStaff", "goodCoffee", "soloOk"])
        case .nature:
            return keys(["greatView", "crowded", "needsWalk", "mosquitoes", "goodLight", "soloOk"])
        case .culture:
            return keys(["worthIt", "needsQuiet", "photoOk", "shoesOff", "entryFee", "soloOk"])
        case .food:
            return keys(["bigPortion", "longQueue", "soloFriendly", "notSpicy", "cheap", "friendlyStaff"])
        case .wellness:
            return keys(["goodStaff", "fewPeople", "comfySpace", "pricey", "needsBooking", "soloOk"])
        case .nightlife:
            return keys(["fewPeople", "soloOk", "goodMusic", "pricey", "safe", "friendlyStaff"])
        case .hidden:
            return keys(["trulyHidden", "worthFinding", "hardToFind", "veryFew", "soloOk"])
        }
    }
}

// MARK: - Best-time ribbon

/// Warm amber best-time ribbon: a sunken track with a golden "good window" band,
/// a smooth crowd-density curve overlay, and a "此刻" now marker — a SwiftUI port
/// of the design's `.sc-best-window-v2` + `CrowdCurve`.
struct BestTimeRibbon: View {
    let windows: [TimeWindow]
    let reduceMotion: Bool

    /// 25-point crowd density curve (0–1) over 24h, lifted from the design's
    /// `CrowdCurve` pts array — purely decorative rhythm, no numbers.
    private let crowd: [CGFloat] = [
        0.05, 0.05, 0.05, 0.05, 0.08, 0.15, 0.32, 0.55, 0.6, 0.45, 0.35, 0.4,
        0.55, 0.5, 0.42, 0.38, 0.45, 0.6, 0.72, 0.65, 0.5, 0.32, 0.18, 0.1, 0.05,
    ]
    private let trackHeight: CGFloat = 38

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            // 0 / 6 / 12 / 18 / 24 scale
            HStack {
                ForEach([0, 6, 12, 18, 24], id: \.self) { h in
                    Text("\(h)").font(CT.mono(9.5)).foregroundStyle(CT.fgSubtle)
                    if h != 24 { Spacer() }
                }
            }
            TimelineView(.periodic(from: .now, by: 60)) { context in
                let nowFraction = nowFraction(for: context.date)
                GeometryReader { geo in
                    let w = geo.size.width
                    ZStack(alignment: .topLeading) {
                        // Golden good-window bands
                        ForEach(Array(windows.enumerated()), id: \.offset) { _, win in
                            ForEach(Array(windowBands(win).enumerated()), id: \.offset) { _, band in
                                LinearGradient(
                                    colors: [CT.sunGoldSoft, CT.sunGold, CT.sunGoldSoft],
                                    startPoint: .leading, endPoint: .trailing
                                )
                                .frame(width: max(2, band.width * w))
                                .offset(x: band.start * w)
                                .opacity(0.85)
                            }
                        }
                        // Crowd-density curve
                        crowdPath(in: geo.size)
                            .stroke(CT.accent.opacity(0.32), lineWidth: 1)
                        // Now marker
                        nowMarker
                            .offset(x: nowFraction * w - 0.75)
                    }
                }
                .frame(height: trackHeight)
                .background(RoundedRectangle(cornerRadius: 8).fill(CT.surfaceSunken))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .padding(.top, 16)
            }
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 14).fill(CT.surfaceWhite))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(CT.borderSubtle, lineWidth: 0.5))
    }

    private var nowMarker: some View {
        VStack(spacing: 0) {
            Circle().fill(CT.accent).frame(width: 7, height: 7).offset(y: -3)
            Rectangle().fill(CT.accent).frame(width: 1.5)
        }
        .frame(height: trackHeight)
    }

    private func nowFraction(for date: Date) -> CGFloat {
        let c = Calendar.current.dateComponents([.hour, .minute], from: date)
        return (CGFloat(c.hour ?? 0) + CGFloat(c.minute ?? 0) / 60) / 24
    }

    private struct Band { let start: CGFloat; let width: CGFloat }

    /// Window → 0…1 fractional bands (splits a midnight-wrapping window in two).
    private func windowBands(_ win: TimeWindow) -> [Band] {
        let s = CGFloat(win.startHour) / 24, e = CGFloat(win.endHour) / 24
        if win.startHour <= win.endHour {
            return [Band(start: s, width: e - s)]
        }
        return [Band(start: s, width: 1 - s), Band(start: 0, width: e)]
    }

    private func crowdPath(in size: CGSize) -> Path {
        Path { p in
            let stepX = size.width / CGFloat(crowd.count - 1)
            func y(_ v: CGFloat) -> CGFloat { size.height - (v * (size.height - 6)) - 2 }
            p.move(to: CGPoint(x: 0, y: y(crowd[0])))
            for i in 1..<crowd.count {
                let x = CGFloat(i) * stepX
                let prevX = CGFloat(i - 1) * stepX
                let cx = prevX + stepX / 2
                p.addCurve(
                    to: CGPoint(x: x, y: y(crowd[i])),
                    control1: CGPoint(x: cx, y: y(crowd[i - 1])),
                    control2: CGPoint(x: cx, y: y(crowd[i]))
                )
            }
        }
    }
}
