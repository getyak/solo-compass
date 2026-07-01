import SwiftUI

/// P2.4 #242: full-screen accept animation when a ripe capsule is
/// opened. Ceremonial surface — capsuleGlow + slow reveal.
public struct CapsuleOpenView: View {

    public struct PayloadRender: Hashable {
        public let title: String
        public let bodyText: String
        public let buriedAt: Date
        public let contextLine: String?

        public init(title: String, bodyText: String, buriedAt: Date, contextLine: String? = nil) {
            self.title = title
            self.bodyText = bodyText
            self.buriedAt = buriedAt
            self.contextLine = contextLine
        }
    }

    public let payload: PayloadRender
    public let onDismiss: () -> Void
    public let onReply: () -> Void

    @State private var revealed = false

    public init(
        payload: PayloadRender,
        onDismiss: @escaping () -> Void,
        onReply: @escaping () -> Void
    ) {
        self.payload = payload
        self.onDismiss = onDismiss
        self.onReply = onReply
    }

    public var body: some View {
        ZStack {
            LinearGradient(
                colors: [CT.capsuleGlow.opacity(0.85), CT.accentSoft],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack(spacing: 24) {
                Spacer()
                Image(systemName: "envelope.open.fill")
                    .font(.system(size: 44, weight: .light))
                    .foregroundColor(CT.omenGold)
                    .scaleEffect(revealed ? 1.0 : 0.75)
                    .opacity(revealed ? 1 : 0.3)

                Text(payload.title)
                    .font(.title2.weight(.semibold))
                    .foregroundColor(CT.fgPrimary)

                Text(payload.bodyText)
                    .font(.system(size: 18, design: .serif))
                    .foregroundColor(CT.fgPrimary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
                    .opacity(revealed ? 1 : 0)
                    .animation(.easeOut(duration: 1.1).delay(0.2), value: revealed)

                if let line = payload.contextLine {
                    Text(line)
                        .font(.footnote.italic())
                        .foregroundColor(CT.fgMuted)
                        .opacity(revealed ? 1 : 0)
                        .animation(.easeOut(duration: 1.1).delay(0.6), value: revealed)
                }

                Text(payload.buriedAt.formatted(date: .abbreviated, time: .omitted))
                    .font(.caption)
                    .foregroundColor(CT.fgSubtle)

                Spacer()

                VStack(spacing: 8) {
                    Button(action: onReply) {
                        Label("Reply to yourself", systemImage: "arrow.uturn.up")
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(CT.omenGold)
                            .foregroundColor(.white)
                            .cornerRadius(20)
                    }
                    Button("Close", action: onDismiss)
                        .font(.footnote)
                        .foregroundColor(CT.fgMuted)
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 24)
            }
            .animation(.easeOut(duration: 0.6), value: revealed)
        }
        .onAppear {
            revealed = true
        }
    }
}

#Preview {
    CapsuleOpenView(
        payload: .init(
            title: "You wrote:",
            bodyText: "Bring back the person who chose the slower path here.",
            buriedAt: Date(),
            contextLine: "You were into: quiet, sunlit, unrushed"
        ),
        onDismiss: {},
        onReply: {}
    )
}
