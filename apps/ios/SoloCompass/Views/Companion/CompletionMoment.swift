import SwiftUI
import SwiftData

// MARK: - CompletionMoment

/// Full-screen celebratory moment shown when a host taps '标记完成' on a closed route.
/// Dispatches closed→completed via RouteCompanionRemote.markCompleted.
public struct CompletionMoment: View {
    let route: Route
    var onDismiss: () -> Void

    private let remoteProvider: @MainActor () -> any RouteCompanionRemote

    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var pulse: Bool = false
    @State private var appeared: Bool = false

    public init(
        route: Route,
        onDismiss: @escaping () -> Void = {},
        remoteProvider: (@MainActor () -> any RouteCompanionRemote)? = nil
    ) {
        self.route = route
        self.onDismiss = onDismiss
        self.remoteProvider = remoteProvider ?? { @MainActor in
            makeRouteCompanionRemote(context: ModelContext(SoloCompassModelContainer.shared))
        }
    }

    // MARK: - Body

    public var body: some View {
        ZStack(alignment: .topTrailing) {
            backgroundGradient

            VStack(spacing: 32) {
                Spacer()
                verifiedIndicator
                statRow
                tagline
                Spacer()
            }
            .padding(.horizontal, 28)
            .accessibilityElement(children: .combine)
            .accessibilityLabel(String(
                format: NSLocalizedString("completion.a11y", comment: ""),
                route.verification.walkedByCount,
                route.companion?.confirmedMembers.count ?? 0
            ))

            closeButton
        }
        .ignoresSafeArea()
        .onAppear {
            if reduceMotion {
                appeared = true
                pulse = false
            } else {
                withAnimation(.easeIn(duration: 0.4)) { appeared = true }
                withAnimation(
                    .easeInOut(duration: 1.2)
                    .repeatForever(autoreverses: true)
                ) {
                    pulse = true
                }
            }
            markCompleted()
        }
        .opacity(appeared ? 1 : 0)
    }

    // MARK: - Sub-views

    private var backgroundGradient: some View {
        LinearGradient(
            colors: [Color(red: 0.05, green: 0.12, blue: 0.22), Color(red: 0.08, green: 0.22, blue: 0.18)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private var verifiedIndicator: some View {
        ZStack {
            Circle()
                .fill(.white.opacity(0.08))
                .frame(width: 160, height: 160)
                .scaleEffect(pulse ? 1.06 : 1.0)

            Image(systemName: "checkmark.seal.fill")
                .resizable()
                .scaledToFit()
                .frame(width: 90, height: 90)
                .foregroundStyle(
                    LinearGradient(
                        colors: [Color(red: 0.2, green: 0.9, blue: 0.7), Color(red: 0.1, green: 0.7, blue: 0.5)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        }
    }

    private var statRow: some View {
        HStack(spacing: 20) {
            statPill(
                icon: "figure.walk",
                label: NSLocalizedString("completion.stat.walked", comment: "") + " x\(route.verification.walkedByCount)"
            )
            statPill(
                icon: "person.2.fill",
                label: NSLocalizedString("completion.stat.travelers", comment: "") + " x\(route.companion?.confirmedMembers.count ?? 0)"
            )
        }
    }

    private func statPill(icon: String, label: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white.opacity(0.8))
            Text(label)
                .font(.system(size: 14, weight: .semibold, design: .monospaced))
                .foregroundStyle(.white.opacity(0.9))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(Capsule().fill(.white.opacity(0.12)))
    }

    private var tagline: some View {
        Text(NSLocalizedString("completion.tagline", comment: ""))
            .font(.system(size: 16, weight: .medium))
            .foregroundStyle(.white.opacity(0.75))
            .multilineTextAlignment(.center)
            .lineLimit(2)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var closeButton: some View {
        Button {
            dismiss()
            onDismiss()
        } label: {
            Image(systemName: "xmark.circle.fill")
                .font(.system(size: 28))
                .foregroundStyle(.white.opacity(0.7))
        }
        .padding(.top, 56)
        .padding(.trailing, 20)
    }

    // MARK: - markCompleted

    private func markCompleted() {
        Task { @MainActor in
            let remote = remoteProvider()
            do {
                try await remote.markCompleted(routeId: route.id)
            } catch is NotImplementedError {
                // Supabase stub not yet implemented — no-op.
            } catch {
                // Illegal state transitions are non-fatal at this display layer.
            }
        }
    }
}

// MARK: - Preview

#Preview("CompletionMoment — mekong-sunset") {
    let companion = RouteCompanion(
        status: .closed,
        hostId: "host-preview",
        departureWindow: DepartureWindow(startDate: "2026-06-01", to: "2026-06-03", time: "morning"),
        departureLabel: "Early June",
        pacePreference: .relaxed,
        maxMembers: 4,
        confirmedMembers: ["user-a", "user-b", "user-c"]
    )
    let route = Route(
        id: RouteId(rawValue: "mekong-sunset"),
        title: "Mekong Sunset Walk",
        summary: "",
        experienceIds: [],
        cityCode: "VTE",
        region: "Riverfront",
        estimatedDuration: 90,
        distanceMeters: 1200,
        pace: .relaxed,
        source: .editorial,
        verification: RouteVerification(status: .walkedBy, walkedByCount: 15, walkedBy: ["maya", "leo"]),
        companion: companion
    )
    CompletionMoment(route: route, onDismiss: {})
}
