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
    @State private var dragOffset: CGFloat = 0
    @State private var crossedThreshold = false
    @State private var pulse = false
    @State private var countdownProgress: CGFloat = 1
    @State private var autoDismissTask: Task<Void, Never>?
    private let dismissThreshold: CGFloat = 80

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
                        #if canImport(UIKit)
                        Haptics.notify(.success)
                        #endif
                        autoDismissTask?.cancel()
                        autoDismissTask = nil
                        onConfirm()
                    } label: {
                        Text(NSLocalizedString("checkin.banner.yes", comment: "Yes!"))
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Capsule().fill(.blue))
                            .foregroundStyle(.white)
                            .scaleEffect(reduceMotion ? 1.0 : (pulse ? 1.04 : 1.0))
                            .animation(reduceMotion ? nil : .easeInOut(duration: 1.3).repeatForever(autoreverses: true), value: pulse)
                    }
                    .buttonStyle(.plain)

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
                    .accessibilityLabel(Text(NSLocalizedString("common.dismiss", comment: "Dismiss")))
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, reduceMotion ? 12 : 18)

            if !reduceMotion {
                GeometryReader { geo in
                    Capsule()
                        .fill(Color.blue)
                        .frame(width: geo.size.width * countdownProgress, height: 2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(height: 2)
                .padding(.horizontal, 2)
                .padding(.bottom, 4)
            }
        }
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
        .shadow(color: .black.opacity(0.12), radius: 8, y: 4)
        .padding(.horizontal, 16)
        .offset(y: dragOffset)
        .gesture(
            DragGesture()
                .onChanged { gesture in
                    dragOffset = min(0, gesture.translation.height * 0.85)
                    let overThreshold = -gesture.translation.height > dismissThreshold
                    if overThreshold && !crossedThreshold {
                        crossedThreshold = true
                        #if canImport(UIKit)
                        Haptics.selection()
                        #endif
                    } else if !overThreshold && crossedThreshold {
                        crossedThreshold = false
                    }
                }
                .onEnded { gesture in
                    if gesture.translation.height < -dismissThreshold {
                        #if canImport(UIKit)
                        Haptics.impact(.soft)
                        #endif
                        crossedThreshold = false
                        autoDismissTask?.cancel()
                        autoDismissTask = nil
                        withAnimation(.easeOut(duration: 0.2)) { dragOffset = -200 }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { onDismiss() }
                    } else {
                        crossedThreshold = false
                        withAnimation(.spring(response: 0.3)) { dragOffset = 0 }
                    }
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
                scheduleAutoDismiss()
                return
            }
            pulse = true

            let seconds = autoDismissSeconds
            if !voiceOverOn {
                withAnimation(.linear(duration: seconds)) {
                    countdownProgress = 0
                }
            }
            scheduleAutoDismiss()
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

    private func scheduleAutoDismiss() {
        let seconds = autoDismissSeconds
        autoDismissTask = Task {
            try? await Task.sleep(for: .seconds(seconds))
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
        .environment(\.accessibilityReduceMotion, true)
    }
}
