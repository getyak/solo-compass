import SwiftUI

/// One-shot confetti burst + checkmark pop overlay fired when an experience is
/// marked complete. Driven by `trigger`: each increment spawns a new burst.
/// Respects Reduce Motion: skips particles, only shows the checkmark pop.
public struct CompletionCelebrationView: View {
    let trigger: Int

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private struct Particle: Identifiable {
        let id = UUID()
        let color: Color
        let angle: Double       // radians
        let distance: CGFloat   // launch radius
        let size: CGFloat
        let isCircle: Bool
        let rotation: Double    // final spin in degrees, random -180...180
        let delay: Double       // stagger offset, random 0...0.08
        let gravity: CGFloat    // downward drift, random 28...46
    }

    @State private var particles: [Particle] = []
    @State private var animated = false
    @State private var checkmarkPop = false

    private static let palette: [Color] = ExperienceCategory.allCases.map(\.color)

    public var body: some View {
        ZStack {
            if !reduceMotion {
                ForEach(particles) { p in
                    Group {
                        if p.isCircle {
                            Circle().fill(p.color)
                        } else {
                            Capsule().fill(p.color)
                        }
                    }
                    .frame(
                        width: p.isCircle ? p.size : p.size * 0.45,
                        height: p.isCircle ? p.size : p.size * 1.4
                    )
                    .offset(
                        x: animated ? cos(p.angle) * p.distance : 0,
                        y: animated ? sin(p.angle) * p.distance + p.gravity : 0
                    )
                    .opacity(animated ? 0 : 0.9)
                    .scaleEffect(animated ? 0.3 : 1.0)
                    .rotationEffect(.degrees(animated ? p.rotation : 0))
                    .animation(
                        .easeOut(duration: 0.8).delay(p.delay),
                        value: animated
                    )
                }
            }

            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 28, weight: .semibold))
                .foregroundStyle(.white)
                .scaleEffect(checkmarkPop ? 1.0 : 0.01)
                .opacity(checkmarkPop ? 1.0 : 0.0)
                .symbolEffect(.bounce, value: checkmarkPop)
        }
        .allowsHitTesting(false)
        .onChange(of: trigger) { _, _ in
            guard trigger > 0 else { return }
            fire()
        }
    }

    // This view owns the completion haptic: success notification immediately,
    // soft impact ~0.12s later synced to the checkmark pop. Haptics.notify/impact
    // guard on Reduce Motion, so nothing fires when particles are also suppressed.
    private func fire() {
        let count = 14
        particles = (0..<count).map { i in
            Particle(
                color: Self.palette[i % Self.palette.count],
                angle: Double(i) / Double(count) * .pi * 2 + Double.random(in: -0.3...0.3),
                distance: CGFloat.random(in: 52...92),
                size: CGFloat.random(in: 6...11),
                isCircle: Bool.random(),
                rotation: Double.random(in: -180...180),
                delay: Double.random(in: 0...0.08),
                gravity: CGFloat.random(in: 28...46)
            )
        }
        animated = false
        checkmarkPop = false

        #if canImport(UIKit)
        Haptics.notify(.success)
        UIAccessibility.post(
            notification: .announcement,
            argument: NSAttributedString(
                string: NSLocalizedString("celebration.complete.a11y", comment: "Experience completed celebration announcement"),
                attributes: [.accessibilitySpeechQueueAnnouncement: true]
            )
        )
        #endif

        withAnimation(.spring(response: 0.15, dampingFraction: 0.6)) {
            checkmarkPop = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
            Haptics.impact(.soft)
        }

        if !reduceMotion {
            withAnimation(.easeOut(duration: 0.8)) {
                animated = true
            }
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.1) {
            particles = []
            animated = false
            checkmarkPop = false
        }
    }
}

#Preview("Burst") {
    struct Demo: View {
        @State private var trigger = 0
        var body: some View {
            ZStack {
                Color(.systemBackground).ignoresSafeArea()
                VStack(spacing: 32) {
                    Button("Fire celebration") { trigger += 1 }
                        .buttonStyle(.borderedProminent)
                    CompletionCelebrationView(trigger: trigger)
                }
            }
        }
    }
    return Demo()
}

#Preview("Reduce Motion") {
    struct Demo: View {
        @State private var trigger = 0
        var body: some View {
            ZStack {
                Color(.systemBackground).ignoresSafeArea()
                VStack(spacing: 32) {
                    Button("Fire (no particles)") { trigger += 1 }
                        .buttonStyle(.borderedProminent)
                    CompletionCelebrationView(trigger: trigger)
                }
            }
        }
    }
    return Demo()
}
