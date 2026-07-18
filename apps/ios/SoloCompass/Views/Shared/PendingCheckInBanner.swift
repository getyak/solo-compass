import SwiftUI

/// Floating banner shown when the user enters a geofenced experience zone.
/// Tapping "Yes, I was there" calls onConfirm; dismissing calls onDismiss.
/// Shown from CompassMapView when MapViewModel.pendingCheckIn is non-nil.
/// Auto-dismisses after `autoDismissSeconds` if the user takes no action.
public struct PendingCheckInBanner: View {
    let experienceTitle: String
    var onConfirm: () -> Void
    var onDismiss: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOverOn
    @State private var confirmed = false
    @State private var dragOffset: CGFloat = 0
    @State private var pulse = false
    @State private var countdownProgress: CGFloat = 1
    @State private var autoDismissTask: Task<Void, Never>?
    private let dismissThreshold: CGFloat = 80

    public init(
        experienceTitle: String,
        onConfirm: @escaping () -> Void,
        onDismiss: @escaping () -> Void
    ) {
        self.experienceTitle = experienceTitle
        self.onConfirm = onConfirm
        self.onDismiss = onDismiss
    }

    fileprivate init(
        experienceTitle: String,
        onConfirm: @escaping () -> Void,
        onDismiss: @escaping () -> Void,
        isInteracting: Bool
    ) {
        self.experienceTitle = experienceTitle
        self.onConfirm = onConfirm
        self.onDismiss = onDismiss
        self._isInteracting = State(initialValue: isInteracting)
    }

    // Pause/resume interaction tracking
    @State private var isInteracting = false
    /// Remaining fraction [0,1] computed from elapsed time when interaction begins.
    @State private var progressAtPause: CGFloat = 1
    /// Wall-clock instant when the current countdown animation started; nil before first start.
    @State private var countdownStartDate: Date? = nil
    /// The remainingFraction value that was passed into the most recent startCountdown call.
    @State private var countdownStartFraction: CGFloat = 1
    /// Guards pauseCountdown() so it fires only on the first-touch, not every drag event.
    @State private var wasPaused = false
    /// True when ~2 s remain; drives amber color shift on the bar and Yes button.
    @State private var isExpiringSoon = false

    /// 12 s under VoiceOver (reader needs more time), 6 s otherwise.
    var autoDismissSeconds: Double { voiceOverOn ? 12 : 6 }

    public var body: some View {
        ZStack(alignment: .bottom) {
            HStack(spacing: 12) {
                Image(systemName: "figure.walk.circle.fill")
                    .font(.title2)
                    .foregroundStyle(.blue)

                VStack(alignment: .leading, spacing: 2) {
                    Text(NSLocalizedString("checkin.banner.title", comment: "Did you visit?"))
                        .font(.subheadline.weight(.semibold))
                    Text(experienceTitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer()

                HStack(spacing: 8) {
                    Button {
                        guard !confirmed else { return }
                        confirmed = true
                        autoDismissTask?.cancel()
                        autoDismissTask = nil
                        #if canImport(UIKit)
                        Haptics.notify(.success)
                        UIAccessibility.post(
                            notification: .announcement,
                            argument: NSLocalizedString("checkin.banner.confirmed.a11y", comment: "Visit confirmed")
                        )
                        #endif
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.28) { onConfirm() }
                    } label: {
                        Group {
                            if confirmed {
                                Image(systemName: "checkmark")
                                    .font(.caption.weight(.semibold))
                                    .contentTransition(.symbolEffect(.replace))
                            } else {
                                Text(NSLocalizedString("checkin.banner.yes", comment: "Yes!"))
                                    .font(.caption.weight(.semibold))
                            }
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Capsule().fill(confirmed ? CT.verifiedGreen : (isExpiringSoon ? CT.warningText : Color.accentColor)))
                        .foregroundStyle(.white)
                        .scaleEffect(reduceMotion ? 1.0 : (confirmed ? 1.0 : (pulse ? 1.04 : 1.0)))
                        .animation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.6), value: confirmed)
                        .animation(reduceMotion ? nil : .easeInOut(duration: 1.3).repeatForever(autoreverses: true), value: pulse)
                    }
                    .buttonStyle(.plain)
                    .disabled(confirmed)

                    Button {
                        autoDismissTask?.cancel()
                        autoDismissTask = nil
                        onDismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.secondary)
                            .frame(width: 28, height: 28)
                            .background(Circle().fill(Color(.secondarySystemFill)))
                    }
                    .buttonStyle(.plain)
                    .disabled(confirmed)
                    .accessibilityLabel(Text(NSLocalizedString("common.dismiss", comment: "Dismiss")))
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, reduceMotion ? 12 : 18)

            if !reduceMotion {
                GeometryReader { geo in
                    Capsule()
                        .fill(isInteracting ? CT.fgMuted : (isExpiringSoon ? CT.warningText : Color.accentColor))
                        .frame(width: geo.size.width * countdownProgress, height: 2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .opacity(isInteracting ? 0.4 : 1.0)
                        .animation(.easeInOut(duration: 0.2), value: isInteracting)
                }
                .frame(height: 2)
                .padding(.horizontal, 2)
                .padding(.bottom, 4)
            }
        }
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
        .shadow(color: .black.opacity(0.12), radius: 8, y: 4)
        .padding(.horizontal, 16)
        // Shared drag-to-dismiss: this banner sits at the top and leaves *up*.
        // The reusable modifier gives it the same 1:1 tracking + momentum
        // projection + velocity-continuous settle as BottomInfoSheet/ChatCard,
        // replacing the old hand-rolled `* 0.85` + release-point-threshold code
        // that neither tracked 1:1 nor honoured a quick flick. The countdown
        // pause/resume hooks onto the modifier's began/cancel callbacks.
        .dismissibleBanner(
            offset: $dragOffset,
            edge: .up,
            threshold: dismissThreshold,
            isEnabled: !confirmed,
            onDragBegan: {
                // Pause the auto-dismiss countdown the instant a drag starts.
                if !wasPaused {
                    wasPaused = true
                    isInteracting = true
                    pauseCountdown()
                }
            },
            onDismiss: {
                autoDismissTask?.cancel()
                autoDismissTask = nil
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { onDismiss() }
            },
            onCancel: {
                // Released below threshold → resume the countdown where it paused.
                isInteracting = false
                wasPaused = false
                startCountdown(remainingFraction: progressAtPause)
            }
        )
        .onAppear {
            #if canImport(UIKit)
            UIAccessibility.post(
                notification: .announcement,
                argument: String(
                    format: NSLocalizedString("checkin.banner.a11yAnnouncement", comment: "VoiceOver announcement when check-in banner appears"),
                    experienceTitle
                )
            )
            #endif
            guard !reduceMotion else {
                pulse = true
                scheduleAutoDismiss(remainingFraction: 1)
                return
            }
            pulse = true
            startCountdown(remainingFraction: 1)
        }
        .onDisappear {
            autoDismissTask?.cancel()
            autoDismissTask = nil
        }
        .transition(.move(edge: .bottom).combined(with: .opacity))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text(String(
            format: NSLocalizedString("checkin.banner.a11y", comment: "Did you visit %@?"),
            experienceTitle
        )))
    }

    /// Starts (or resumes) the animated countdown bar and the auto-dismiss task.
    /// `remainingFraction` is in [0, 1] where 1 means full duration remaining.
    private func startCountdown(remainingFraction: CGFloat) {
        isExpiringSoon = false
        countdownStartDate = Date()
        countdownStartFraction = remainingFraction
        guard !voiceOverOn else {
            // VoiceOver: no bar, just arm the dismiss task.
            scheduleAutoDismiss(remainingFraction: remainingFraction)
            return
        }
        let remaining = autoDismissSeconds * Double(remainingFraction)
        withAnimation(.linear(duration: remaining)) {
            countdownProgress = 0
        }
        scheduleAutoDismiss(remainingFraction: remainingFraction)
    }

    /// Cancels the auto-dismiss task and freezes the countdown bar at its current value.
    private func pauseCountdown() {
        autoDismissTask?.cancel()
        autoDismissTask = nil
        isExpiringSoon = false
        // Compute remaining fraction from elapsed wall-clock time, not the state variable
        // (which holds the animation TARGET 0, not the in-flight rendered position).
        if let start = countdownStartDate {
            let totalSeconds = autoDismissSeconds * Double(countdownStartFraction)
            let elapsed = Date().timeIntervalSince(start)
            let remaining = max(0, totalSeconds - elapsed)
            progressAtPause = CGFloat(remaining / autoDismissSeconds)
        } else {
            progressAtPause = countdownStartFraction
        }
        // Freeze the bar at the computed position.
        withAnimation(.linear(duration: 0)) {
            countdownProgress = progressAtPause
        }
    }

    private func scheduleAutoDismiss(remainingFraction: CGFloat) {
        let seconds = autoDismissSeconds * Double(remainingFraction)
        autoDismissTask = Task {
            // Arm the amber warning ~2 s before auto-dismiss (skip under reduceMotion or VoiceOver).
            if seconds > 2 && !reduceMotion && !voiceOverOn {
                try? await Task.sleep(for: .seconds(seconds - 2))
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    withAnimation(.easeInOut) { isExpiringSoon = true }
                    #if canImport(UIKit)
                    Haptics.impact(.soft)
                    #endif
                }
            }
            try? await Task.sleep(for: .seconds(seconds > 2 && !reduceMotion && !voiceOverOn ? 2 : seconds))
            guard !Task.isCancelled else { return }
            await MainActor.run {
                onDismiss()
            }
        }
    }
}

#Preview("Countdown bar") {
    ZStack(alignment: .bottom) {
        Color(.systemGroupedBackground).ignoresSafeArea()
        PendingCheckInBanner(
            experienceTitle: "Watch the monks collect alms at dawn",
            onConfirm: {},
            onDismiss: {}
        )
        .padding(.bottom, 40)
    }
}

#Preview("Reduce Motion") {
    ZStack(alignment: .bottom) {
        Color(.systemGroupedBackground).ignoresSafeArea()
        PendingCheckInBanner(
            experienceTitle: "Watch the monks collect alms at dawn",
            onConfirm: {},
            onDismiss: {}
        )
        .padding(.bottom, 40)
        // NOTE: `accessibilityReduceMotion` is a READ-ONLY EnvironmentValue —
        // SwiftUI exposes no writable setter, so it cannot be injected here.
        // To preview the reduce-motion path, toggle the Simulator's
        // Settings → Accessibility → Motion → Reduce Motion. The previous
        // `.environment(\.accessibilityReduceMotion, true)` broke the build
        // (KeyPath is not a WritableKeyPath).
    }
}

#Preview("Paused state") {
    ZStack(alignment: .bottom) {
        Color(.systemGroupedBackground).ignoresSafeArea()
        PendingCheckInBanner(
            experienceTitle: "Watch the monks collect alms at dawn",
            onConfirm: {},
            onDismiss: {},
            isInteracting: true
        )
        .padding(.bottom, 40)
    }
}
