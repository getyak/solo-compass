import SwiftUI

/// P2.3 #230: full-screen launch UI for a blindbox trip.
public struct BlindboxLaunchView: View {

    public enum Duration: String, CaseIterable, Identifiable {
        case oneHour = "1h"
        case threeHours = "3h"
        case allDay = "all-day"

        public var id: String { rawValue }
        public var hours: Double {
            switch self {
            case .oneHour: return 1
            case .threeHours: return 3
            case .allDay: return 8
            }
        }
    }

    @State private var selected: Duration = .threeHours
    public let onLaunch: (Duration) -> Void
    public let onDismiss: () -> Void

    public init(
        onLaunch: @escaping (Duration) -> Void,
        onDismiss: @escaping () -> Void
    ) {
        self.onLaunch = onLaunch
        self.onDismiss = onDismiss
    }

    public var body: some View {
        ZStack {
            LinearGradient(
                colors: [CT.blindboxAmber.opacity(0.88), CT.sunGoldDeep.opacity(0.72)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            VStack(spacing: 28) {
                Spacer()
                Text("Blindbox")
                    .font(.largeTitle.weight(.bold))
                    .foregroundColor(.white)
                Text("Three anchor stops. We reveal each when you arrive. No rush, no preview.")
                    .font(.callout)
                    .foregroundColor(.white.opacity(0.85))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 28)

                Picker("Duration", selection: $selected) {
                    ForEach(Duration.allCases) { d in
                        Text(d.rawValue).tag(d)
                    }
                }
                .pickerStyle(.segmented)
                .tint(.white)
                .padding(.horizontal, 40)

                Spacer()

                Button(action: { onLaunch(selected) }) {
                    Text("Open")
                        .font(.title3.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Color.white)
                        .foregroundColor(CT.blindboxAmber)
                        .cornerRadius(24)
                        .padding(.horizontal, 24)
                }

                Button("Not now", action: onDismiss)
                    .font(.footnote)
                    .foregroundColor(.white.opacity(0.7))
                    .padding(.bottom, 20)
            }
        }
    }
}

#Preview {
    BlindboxLaunchView(onLaunch: { _ in }, onDismiss: {})
}
