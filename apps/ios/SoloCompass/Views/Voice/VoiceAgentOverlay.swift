import SwiftUI

/// Inline voice agent mode overlaid directly on the map (no sheet).
///
/// Lifecycle:
///   1. Long-press triggers → overlay appears, `isListening = true`
///   2. While holding: pulsing orb + live transcript above the orb
///   3. On release: transcript sent to orchestrator, orb switches to
///      "thinking" animation while AI responds
///   4. Tap ✕ or wait for response to finish → overlay dismisses
///
/// The overlay owns the VoiceService interaction for the hold gesture.
/// The parent (CompassMapView) owns the orchestrator lifecycle.
@MainActor
public struct VoiceAgentOverlay: View {
    public let orchestrator: VoiceAgentOrchestrator
    public let voiceService: VoiceService
    /// Called when the user dismisses the overlay (✕ button).
    public var onDismiss: () -> Void

    @State private var isHolding: Bool = false
    @State private var liveTranscript: String = ""
    @State private var pulse: Bool = false
    @State private var voiceStreamTask: Task<Void, Never>? = nil
    @State private var permissionDenied: Bool = false

    public init(
        orchestrator: VoiceAgentOrchestrator,
        voiceService: VoiceService,
        onDismiss: @escaping () -> Void
    ) {
        self.orchestrator = orchestrator
        self.voiceService = voiceService
        self.onDismiss = onDismiss
    }

    private var session: VoiceAgentSession { orchestrator.session }

    public var body: some View {
        VStack(spacing: 0) {
            Spacer()

            // Permission denied banner
            if permissionDenied {
                HStack(spacing: 8) {
                    Image(systemName: "mic.slash.fill")
                        .foregroundStyle(.orange)
                    Text(NSLocalizedString("voiceAgent.permissionDenied", comment: "Microphone access needed — enable in Settings"))
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.primary)
                    Spacer()
                    Button {
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            UIApplication.shared.open(url)
                        }
                    } label: {
                        Text(NSLocalizedString("common.settings", comment: "Settings"))
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.tint)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                .padding(.horizontal, 24)
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .padding(.bottom, 12)
            }

            // Live transcript floats above the orb
            if isHolding, !liveTranscript.isEmpty {
                Text(liveTranscript)
                    .font(.subheadline)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.primary)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
                    .padding(.horizontal, 32)
                    .shadow(color: .black.opacity(0.1), radius: 4, y: 2)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
                    .padding(.bottom, 12)
            }

            // Hold-to-speak label
            Text(holdLabel)
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
                .padding(.bottom, 8)
                .transition(.opacity)

            // Pulsing orb
            ZStack {
                // Outer pulse rings
                ForEach(0..<2) { i in
                    Circle()
                        .stroke(orbColor.opacity(0.35 - Double(i) * 0.12), lineWidth: 3)
                        .frame(width: 80 + CGFloat(i) * 24, height: 80 + CGFloat(i) * 24)
                        .scaleEffect(pulse ? 1.15 : 0.9)
                        .opacity(pulse ? 0.0 : 0.9)
                        .animation(
                            .easeOut(duration: 1.1 + Double(i) * 0.2)
                                .repeatForever(autoreverses: false)
                                .delay(Double(i) * 0.25),
                            value: pulse
                        )
                }

                // Core orb
                Circle()
                    .fill(orbColor)
                    .frame(width: 72, height: 72)
                    .shadow(color: orbColor.opacity(0.4), radius: isHolding ? 16 : 6, y: 4)

                // Icon
                Group {
                    switch orbIcon {
                    case .mic:
                        Image(systemName: "mic.fill")
                            .font(.title2.weight(.semibold))
                            .symbolEffect(.variableColor.iterative, isActive: isHolding)
                    case .waveform:
                        Image(systemName: "waveform")
                            .font(.title2.weight(.semibold))
                            .symbolEffect(.variableColor.iterative, isActive: true)
                    case .thinking:
                        ProgressView()
                            .progressViewStyle(.circular)
                            .tint(.white)
                            .scaleEffect(1.2)
                    }
                }
                .foregroundStyle(.white)
            }
            .gesture(
                LongPressGesture(minimumDuration: 0.01)
                    .onEnded { _ in beginHolding() }
            )
            .simultaneousGesture(
                DragGesture(minimumDistance: 0)
                    .onEnded { _ in if isHolding { endHolding() } }
            )
            .accessibilityLabel(Text(NSLocalizedString("voiceAgent.orb.a11y", comment: "Hold to speak to Solo Compass")))
            .accessibilityHint(Text(NSLocalizedString("voiceAgent.orb.hint", comment: "Double tap and hold to speak")))
            .accessibilityAddTraits(.startsMediaSession)

            // Dismiss button
            Button(action: onDismiss) {
                Image(systemName: "xmark.circle.fill")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
            .padding(.top, 16)
            .accessibilityLabel(Text(NSLocalizedString("common.close", comment: "Close")))

            Spacer().frame(height: 24)
        }
        .onAppear {
            pulse = true
        }
        .onDisappear {
            voiceStreamTask?.cancel()
            voiceService.stopListening()
        }
        .animation(.easeInOut(duration: 0.2), value: isHolding)
        .animation(.easeInOut(duration: 0.2), value: liveTranscript.isEmpty)
    }

    // MARK: - Orb state

    private enum OrbIcon { case mic, waveform, thinking }

    private var isAgentActive: Bool {
        switch session.state {
        case .thinking, .toolExecuting: return true
        default: return false
        }
    }

    private var orbIcon: OrbIcon {
        if orchestrator.isExecutingTool || isAgentActive { return .thinking }
        if isHolding { return .waveform }
        return .mic
    }

    private var orbColor: Color {
        if isHolding { return .red }
        if isAgentActive { return Color.blue }
        if session.state == .speaking { return Color.green }
        return Color.black.opacity(0.85)
    }

    private var holdLabel: String {
        if isHolding { return liveTranscript.isEmpty
            ? NSLocalizedString("voiceAgent.orb.listening", comment: "Listening…")
            : NSLocalizedString("voiceAgent.orb.release", comment: "Release to send")
        }
        if isAgentActive || orchestrator.isExecutingTool {
            return orchestrator.thinkingStep
        }
        if session.state == .speaking {
            return NSLocalizedString("voiceAgent.orb.responding", comment: "Responding…")
        }
        return NSLocalizedString("voiceAgent.orb.holdToSpeak", comment: "Hold to speak")
    }

    // MARK: - Voice recording

    private func beginHolding() {
        guard !isHolding else { return }
        // Re-enter listening state for subsequent turns (first turn is set by start()).
        if session.state == .idle { session.beginListening() }
        Task {
            let granted = await voiceService.requestPermission()
            guard granted else {
                withAnimation(.easeInOut(duration: 0.25)) { permissionDenied = true }
                return
            }
            withAnimation { permissionDenied = false }
            do {
                isHolding = true
                liveTranscript = ""
                let stream = try voiceService.startListening()
                voiceStreamTask = Task { @MainActor in
                    do {
                        for try await text in stream {
                            liveTranscript = text
                        }
                    } catch {
                        isHolding = false
                    }
                }
            } catch {
                isHolding = false
            }
        }
    }

    private func endHolding() {
        guard isHolding else { return }
        voiceService.stopListening()
        voiceStreamTask?.cancel()
        voiceStreamTask = nil
        isHolding = false
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        let final = liveTranscript
        liveTranscript = ""
        if !final.isEmpty {
            orchestrator.handleTranscript(final)
        }
    }
}

#Preview {
    let orch = VoiceAgentOrchestrator(
        aiService: AIService(),
        voiceService: VoiceService(),
        mapViewModel: MapViewModel(
            locationService: LocationService.shared,
            experienceService: ExperienceService(),
            aiService: AIService(),
            preferences: UserPreferences()
        ),
        preferences: UserPreferences()
    )
    return ZStack {
        Color.gray.opacity(0.15).ignoresSafeArea()
        VoiceAgentOverlay(
            orchestrator: orch,
            voiceService: VoiceService(),
            onDismiss: {}
        )
    }
}
