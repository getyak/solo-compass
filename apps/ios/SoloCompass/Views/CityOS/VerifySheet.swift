import SwiftUI

/// City OS v3 · 离店一键印证 (design handoff v2/detail.jsx VerifySheet):
/// three binary questions answerable in 30 seconds, feeding the Recall
/// contribution loop. Submit stays disabled until all three are answered —
/// a half-filled verification is worse than none.
struct VerifySheet: View {
    /// The traveler's three answers, index 0 = the first (positive) option.
    struct Answers: Equatable {
        var stillThere: Int?
        var soloComfort: Int?
        var crowd: Int?

        var isComplete: Bool {
            stillThere != nil && soloComfort != nil && crowd != nil
        }
    }

    let placeName: String
    let onSubmit: (Answers) -> Void
    let onDismiss: () -> Void

    @State private var answers = Answers()
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            question(
                text: NSLocalizedString("cityos.verify.q.exists", comment: "它还在、还开着吗？"),
                options: [
                    NSLocalizedString("cityos.verify.q.exists.yes", comment: "还在 ✓"),
                    NSLocalizedString("cityos.verify.q.exists.no", comment: "变了 / 关了"),
                ],
                selection: $answers.stillThere
            )
            question(
                text: NSLocalizedString("cityos.verify.q.solo", comment: "一个人去，自在吗？"),
                options: [
                    NSLocalizedString("cityos.verify.q.solo.yes", comment: "很自在"),
                    NSLocalizedString("cityos.verify.q.solo.no", comment: "有点尴尬"),
                ],
                selection: $answers.soloComfort
            )
            question(
                text: NSLocalizedString("cityos.verify.q.crowd", comment: "你去的时候人多吗？"),
                options: [
                    NSLocalizedString("cityos.verify.q.crowd.few", comment: "人少"),
                    NSLocalizedString("cityos.verify.q.crowd.many", comment: "挺挤"),
                ],
                selection: $answers.crowd
            )
            submitButton
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(sheetBackground.ignoresSafeArea())
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(NSLocalizedString("cityos.verify.title", comment: "30 秒，帮下一个独行者"))
                .font(CT.displayRounded(18, .bold))
                .foregroundStyle(primaryText)
            Text(String(
                format: NSLocalizedString(
                    "cityos.verify.subtitle",
                    comment: "%@ —— 三下点完，你的印证会直接进入这个点的信心分"
                ),
                placeName
            ))
            .font(CT.body(12.5))
            .foregroundStyle(CT.fgMuted)
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func question(text: String, options: [String], selection: Binding<Int?>) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(text)
                .font(CT.body(13.5, .semibold))
                .foregroundStyle(primaryText)
            HStack(spacing: 8) {
                ForEach(options.indices, id: \.self) { index in
                    optionPill(
                        label: options[index],
                        isSelected: selection.wrappedValue == index
                    ) {
                        Haptics.impact(.light)
                        selection.wrappedValue = index
                    }
                }
            }
        }
    }

    private func optionPill(label: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(CT.body(13, .medium))
                .foregroundStyle(isSelected ? CT.accent : CT.fgMuted)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 9)
                .background(
                    Capsule().fill(isSelected ? CT.accentSoft : optionFill)
                )
                .overlay(
                    Capsule().strokeBorder(
                        isSelected ? CT.accent : borderColor,
                        lineWidth: isSelected ? 1.2 : 0.5
                    )
                )
        }
        .buttonStyle(PressableButtonStyle(pressedScale: 0.97))
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

    private var submitButton: some View {
        Button {
            Haptics.notify(.success)
            onSubmit(answers)
            onDismiss()
        } label: {
            Text(NSLocalizedString("cityos.verify.submit", comment: "提交印证"))
                .font(CT.body(14.5, .semibold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(Capsule().fill(answers.isComplete ? CT.accent : CT.fgSubtle))
        }
        .buttonStyle(PressableButtonStyle(pressedScale: 0.98))
        .disabled(!answers.isComplete)
        .padding(.top, 4)
        .animation(.easeInOut(duration: 0.2), value: answers.isComplete)
    }

    // MARK: - Colors

    private var sheetBackground: Color { colorScheme == .dark ? CT.warmSheetDark : CT.surfaceSunken }
    private var optionFill: Color { colorScheme == .dark ? CT.warmCardDark : CT.surfaceWhite }
    private var borderColor: Color { colorScheme == .dark ? CT.warmBorderDark : CT.borderSubtle }
    private var primaryText: Color { colorScheme == .dark ? CT.fgPrimaryDark : CT.fgPrimary }
}
