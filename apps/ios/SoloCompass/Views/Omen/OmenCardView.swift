import SwiftUI

/// P3.0 #302: renders today's `OmenCardData`. Card flips (via
/// `revealed`) after the user taps "Done" on the micro-task.
public struct OmenCardView: View {

    public let data: OmenCardData
    public let onMicroTaskDone: () -> Void

    @State private var flipped = false

    public init(data: OmenCardData, onMicroTaskDone: @escaping () -> Void) {
        self.data = data
        self.onMicroTaskDone = onMicroTaskDone
    }

    public var body: some View {
        ZStack {
            if flipped { back } else { front }
        }
        .frame(maxWidth: .infinity)
        .padding(24)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(CT.accentSoft)
        )
        .rotation3DEffect(.degrees(flipped ? 180 : 0), axis: (x: 0, y: 1, z: 0))
        .animation(.easeInOut(duration: 0.55), value: flipped)
        .padding(.horizontal, 20)
    }

    private var front: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(dateString)
                .font(.caption.weight(.medium))
                .tracking(1.5)
                .foregroundColor(CT.omenGold)

            Text(data.line)
                .font(.system(size: 22, weight: .semibold, design: .serif))
                .foregroundColor(CT.fgPrimary)
                .fixedSize(horizontal: false, vertical: true)

            Divider().padding(.vertical, 4)

            Text("Micro-task")
                .font(.caption.weight(.medium))
                .foregroundColor(CT.fgMuted)
            Text(data.microTask)
                .font(.callout)
                .foregroundColor(CT.fgPrimary)

            Button("Mark done") {
                flipped = true
                onMicroTaskDone()
            }
            .font(.callout.weight(.semibold))
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(CT.omenGold)
            .foregroundColor(.white)
            .cornerRadius(16)
            .padding(.top, 4)
        }
    }

    private var back: some View {
        VStack(spacing: 12) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 32))
                .foregroundColor(CT.omenGold)
            Text("Kept.")
                .font(.title3.weight(.semibold))
                .foregroundColor(CT.fgPrimary)
            Text("Tomorrow's card is being written.")
                .font(.footnote)
                .foregroundColor(CT.fgMuted)
        }
        .rotation3DEffect(.degrees(180), axis: (x: 0, y: 1, z: 0))
    }

    private var dateString: String {
        let f = DateFormatter()
        f.dateFormat = "EEE, MMM d"
        return f.string(from: data.date).uppercased()
    }
}

#Preview {
    OmenCardView(
        data: .init(
            date: Date(),
            line: "Sit where the light is thin.",
            microTask: "Order the second cheapest coffee.",
            anchorExperienceId: nil,
            anchorTitle: nil
        ),
        onMicroTaskDone: {}
    )
}
