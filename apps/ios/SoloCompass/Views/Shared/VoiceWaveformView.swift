import SwiftUI

/// Siri-like waveform that responds to speaking amplitude.
/// Renders 3 layered gradient ripples via Canvas + TimelineView(.animation).
/// Amplitude range 0–1 maps linearly to ripple amplitude 0–40pt.
public struct VoiceWaveformView: View {
    /// Current audio amplitude 0–1.
    var amplitude: Double
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let maxRippleAmplitude: CGFloat = 40

    public init(amplitude: Double) {
        self.amplitude = max(0, min(1, amplitude))
    }

    public var body: some View {
        if reduceMotion {
            staticWaveform
        } else {
            TimelineView(.animation) { timeline in
                Canvas { context, size in
                    drawRipples(in: &context, size: size, date: timeline.date)
                }
            }
        }
    }

    private var staticWaveform: some View {
        // Reduced-motion: simple ellipse sized to amplitude
        GeometryReader { geo in
            let center = CGPoint(x: geo.size.width / 2, y: geo.size.height / 2)
            let r = CGFloat(amplitude) * Self.maxRippleAmplitude + 20
            Ellipse()
                .stroke(Color.accentColor.opacity(0.4), lineWidth: 2)
                .frame(width: r * 2, height: r * 2)
                .position(center)
        }
    }

    private func drawRipples(in context: inout GraphicsContext, size: CGSize, date: Date) {
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        let amp = CGFloat(amplitude) * Self.maxRippleAmplitude

        // Phase driven by time so ripples animate even at rest
        let t = date.timeIntervalSinceReferenceDate
        let layers: [(phase: Double, opacity: Double, scale: Double)] = [
            (phase: t * 1.2, opacity: 0.55, scale: 1.0),
            (phase: t * 1.2 + 0.8, opacity: 0.35, scale: 1.15),
            (phase: t * 1.2 + 1.6, opacity: 0.2, scale: 1.3),
        ]

        for layer in layers {
            let pulse = CGFloat(sin(layer.phase) * 0.5 + 0.5)   // 0…1
            let r = (20 + amp * CGFloat(layer.scale) + pulse * 8) * CGFloat(layer.scale)
            let rect = CGRect(x: center.x - r, y: center.y - r, width: r * 2, height: r * 2)
            let path = Path(ellipseIn: rect)

            // Gradient from accentColor center outward to transparent
            let gradient = Gradient(colors: [
                Color.accentColor.opacity(layer.opacity),
                Color.accentColor.opacity(0),
            ])
            context.fill(
                path,
                with: .radialGradient(
                    gradient,
                    center: center,
                    startRadius: 0,
                    endRadius: r
                )
            )
        }
    }
}

#Preview("VoiceWaveformView — low amplitude") {
    VStack(spacing: 24) {
        Text("Low (0.1)").font(.caption)
        VoiceWaveformView(amplitude: 0.1)
            .frame(width: 200, height: 200)
    }
    .padding()
}

#Preview("VoiceWaveformView — high amplitude") {
    VStack(spacing: 24) {
        Text("High (0.9)").font(.caption)
        VoiceWaveformView(amplitude: 0.9)
            .frame(width: 200, height: 200)
    }
    .padding()
    .preferredColorScheme(.dark)
}
