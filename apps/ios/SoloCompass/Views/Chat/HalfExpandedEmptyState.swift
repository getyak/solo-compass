import SwiftUI

/// Minimal, breathing entry shown when the chat sheet is parked at the medium
/// detent. The full empty state (large hero + three full-width starter cards)
/// looks crowded at half-height — it reads as a settings panel instead of a
/// doorway to a companion. This layout strips it down to:
///
///   - a slow-breathing `SoloOrb` (the "someone is here"-feeling)
///   - a single serif invitation
///   - a tiny moment chip
///   - four ultra-short suggestion pills (taps fill the full prompt + send)
///   - a centered push-to-talk mic (the primary voice-mode handle)
///
/// Tapping a pill calls `onSendPrompt(fullPrompt)` with the full sentence so
/// the orchestrator gets a complete question. Long-pressing the mic is
/// push-to-talk — `onMicPress(true)` on touch-down, `onMicPress(false)` on
/// release — mirroring `ChatInputBar` so the orchestrator handlers can stay.
@MainActor
struct HalfExpandedEmptyState: View {
    /// Short pill label + the full sentence it expands to when tapped.
    struct Suggestion: Identifiable {
        let id = UUID()
        let label: String       // 2-4 char punchy tag, e.g. "咖啡"
        let icon: String        // SF symbol
        let tint: Color
        let fullPrompt: String  // the actual question to send
    }

    let nowChipText: String
    let suggestions: [Suggestion]
    let onSendPrompt: (String) -> Void
    let onMicPress: (Bool) -> Void
    /// Whether the mic is currently held — drives the orb-style pulse on the
    /// mic button so the user can see they're recording without looking away.
    let isMicListening: Bool

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var appeared = false

    var body: some View {
        // Editorial half-sheet — "B. Minimal Voice":
        //   line 1  language tag  (mood copy, tracked all-caps micro-label)
        //   line 2  serif hero invitation (2 lines, 26pt)
        //   line 3  four punchy pills
        //   line 4  Hold-to-talk mic (single voice entry)
        // Deliberately no orb, no InputBar, no chrome — the sheet's grabber is
        // the only top edge. Chat header, Divider, and textInputBar are all
        // suppressed by `ChatSheet` when `detent == .medium`, so this view IS
        // the whole half-sheet surface.
        VStack(spacing: 0) {
            Spacer(minLength: 20)

            momentTag
                .padding(.bottom, 14)

            Text(NSLocalizedString(
                "chat.empty.half.invite",
                comment: "Half-detent serif invitation — Ask me where to go"
            ))
                .font(.system(size: 26, weight: .semibold, design: .serif))
                .tracking(-0.3)
                .foregroundStyle(titleColor)
                .multilineTextAlignment(.center)
                .lineSpacing(3)
                .padding(.horizontal, 36)
                .padding(.bottom, 22)

            suggestionRow
                .padding(.bottom, 28)

            micHandle

            Spacer(minLength: 20)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .opacity(appeared ? 1 : 0)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.45), value: appeared)
        .onAppear { appeared = true }
    }

    // MARK: - Moment tag (top micro-label)
    //
    // Tiny uppercase language tag instead of the previous filled chip. Reads
    // as an editorial dateline ("LATE · QUIET") rather than a UI badge — no
    // fill, no icon, just tracked letterforms in a warm ink tone. Cues the
    // moment without competing with the serif hero below.
    private var momentTag: some View {
        // Editorial dateline. Tracking is heavy, so long copy
        // ("LATE AND QUIET · A ROOFTOP OR A LAST DRINK") needs a smaller
        // size + gentle downscale rather than a hard truncation ellipsis —
        // truncated all-caps letterforms read like an error, not a design.
        Text(nowChipText.uppercased())
            .font(.system(size: 9.5, weight: .semibold, design: .rounded))
            .tracking(1.8)
            .foregroundStyle(CT.sunGoldDeep.opacity(0.85))
            .lineLimit(1)
            .minimumScaleFactor(0.75)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 28)
    }

    // MARK: - Suggestion row (horizontal pills)
    //
    // Plain HStack — at 4 short tags + 22pt side padding the row fits well
    // under 360pt on every supported width, so the ScrollView's bounce was
    // never used. Removing it also makes the row visible to `ImageRenderer`
    // (which silently drops ScrollView content in snapshot tests).
    private var suggestionRow: some View {
        // Four tags on a 375pt-wide screen with English localizations
        // ("Nearby / Coffee / Sunset / Tonight") overflow the horizontal
        // budget and wrap inside each capsule ("Nearb y"). Icon-only pills
        // instead: label reads out via .accessibilityLabel for VO, and the
        // punchy tag is preserved for the moment chip narrative but not
        // rendered in the row itself.
        HStack(spacing: 10) {
            ForEach(suggestions) { s in
                Button {
                    Haptics.impact(.light)
                    onSendPrompt(s.fullPrompt)
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: s.icon)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(s.tint)
                        Text(s.label)
                            .font(.system(size: 12.5, weight: .semibold))
                            .foregroundStyle(pillTextColor)
                            .lineLimit(1)
                            .minimumScaleFactor(0.85)
                            .fixedSize(horizontal: true, vertical: false)
                    }
                    .padding(.horizontal, 11)
                    .padding(.vertical, 8)
                    .background(pillFill, in: Capsule())
                    .overlay(Capsule().strokeBorder(pillBorder, lineWidth: 0.5))
                }
                .buttonStyle(PressableButtonStyle(pressedScale: 0.92))
                .accessibilityLabel(s.fullPrompt)
            }
        }
        .padding(.horizontal, 16)
    }

    // MARK: - Push-to-talk mic

    private var micHandle: some View {
        ZStack {
            // Outer breathing halo while listening — the user's confirmation
            // they're being heard without breaking attention away from speaking.
            if isMicListening {
                Circle()
                    .fill(CT.accent.opacity(0.18))
                    .frame(width: 84, height: 84)
                    .scaleEffect(isMicListening ? 1.18 : 0.9)
                    .opacity(isMicListening ? 0.0 : 0.9)
                    .animation(
                        reduceMotion ? nil : .easeOut(duration: 1.0).repeatForever(autoreverses: false),
                        value: isMicListening
                    )
            }

            Circle()
                .fill(
                    LinearGradient(
                        colors: isMicListening
                            ? [CT.sunGoldDeep, CT.accent]
                            : [CT.accent, CT.accentHover],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 56, height: 56)
                .overlay(
                    Circle().strokeBorder(Color.white.opacity(0.22), lineWidth: 0.75)
                )
                .overlay(
                    Image(systemName: isMicListening ? "waveform" : "mic.fill")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(.white)
                )
                .shadow(color: CT.accent.opacity(0.28), radius: 10, y: 4)
                .scaleEffect(isMicListening ? 1.06 : 1.0)
                .animation(reduceMotion ? nil : .spring(response: 0.32, dampingFraction: 0.7), value: isMicListening)
        }
        .contentShape(Circle())
        .onLongPressGesture(
            minimumDuration: 0.0,
            maximumDistance: .infinity,
            perform: {},
            onPressingChanged: { pressing in
                onMicPress(pressing)
            }
        )
        .accessibilityLabel(Text(NSLocalizedString(
            "chat.empty.half.mic.a11y",
            comment: "Push and hold to talk to Solo"
        )))
        .accessibilityAddTraits(.isButton)
    }

    // MARK: - Colors

    private var titleColor: Color {
        colorScheme == .dark ? CT.fgPrimaryDark : CT.fgPrimary
    }

    private var pillTextColor: Color {
        colorScheme == .dark ? CT.fgPrimaryDark : CT.fgPrimary
    }

    private var pillFill: Color {
        colorScheme == .dark ? Color(.secondarySystemBackground) : CT.surfaceWhite
    }

    private var pillBorder: Color {
        colorScheme == .dark ? Color(.separator) : CT.borderSubtle
    }
}

#Preview("Half-Expanded Empty — light") {
    HalfExpandedEmptyState(
        nowChipText: "午后柔和 · 适合走走",
        suggestions: [
            .init(label: "附近", icon: "mappin.and.ellipse", tint: CT.accent, fullPrompt: "附近有什么好玩的？"),
            .init(label: "咖啡", icon: "cup.and.saucer.fill", tint: CT.sunGoldDeep, fullPrompt: "找一家安静的咖啡馆"),
            .init(label: "落日", icon: "sun.horizon.fill", tint: CT.sunGoldDeep, fullPrompt: "推荐一个看落日的地方"),
            .init(label: "今晚", icon: "moon.stars.fill", tint: Color(.sRGB, red: 0x6B / 255, green: 0x4E / 255, blue: 0x7D / 255, opacity: 1), fullPrompt: "帮我计划今晚的行程"),
        ],
        onSendPrompt: { _ in },
        onMicPress: { _ in },
        isMicListening: false
    )
    .frame(height: 440)
    .background(CT.bgWarm)
}
