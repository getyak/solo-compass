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
        VStack(spacing: 0) {
            Spacer(minLength: 18)

            SoloOrb(size: 60)
                .padding(.bottom, 18)

            Text(NSLocalizedString(
                "chat.empty.half.invite",
                comment: "Half-detent serif invitation — Ask me where to go"
            ))
                .font(.system(size: 19, weight: .semibold, design: .serif))
                .foregroundStyle(titleColor)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
                .padding(.bottom, 10)

            momentChip
                .padding(.bottom, 18)

            suggestionRow
                .padding(.bottom, 22)

            micHandle
                .padding(.bottom, 6)

            Text(NSLocalizedString(
                "chat.empty.half.micHint",
                comment: "Micro caption under push-to-talk mic"
            ))
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(.secondary)
                .opacity(isMicListening ? 0 : 1)

            Spacer(minLength: 14)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .opacity(appeared ? 1 : 0)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.45), value: appeared)
        .onAppear { appeared = true }
    }

    // MARK: - Moment chip

    private var momentChip: some View {
        HStack(spacing: 6) {
            Image(systemName: "sun.haze.fill")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(CT.sunGoldDeep)
            Text(nowChipText)
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(CT.sunGoldDeep)
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 5)
        .background(Capsule().fill(CT.sunGoldSoft))
    }

    // MARK: - Suggestion row (horizontal pills)
    //
    // Plain HStack — at 4 short tags + 22pt side padding the row fits well
    // under 360pt on every supported width, so the ScrollView's bounce was
    // never used. Removing it also makes the row visible to `ImageRenderer`
    // (which silently drops ScrollView content in snapshot tests).
    private var suggestionRow: some View {
        HStack(spacing: 8) {
            ForEach(suggestions) { s in
                Button {
                    Haptics.impact(.light)
                    onSendPrompt(s.fullPrompt)
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: s.icon)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(s.tint)
                        Text(s.label)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(pillTextColor)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(pillFill, in: Capsule())
                    .overlay(Capsule().strokeBorder(pillBorder, lineWidth: 0.5))
                }
                .buttonStyle(PressableButtonStyle(pressedScale: 0.92))
                .accessibilityLabel(s.fullPrompt)
            }
        }
        .padding(.horizontal, 22)
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
