import SwiftUI

/// P2.4 #241: compose sheet for burying a time capsule.
public struct CapsuleComposeView: View {

    public let experienceId: String
    public let experienceTitle: String
    public let onBury: (Payload) -> Void
    public let onCancel: () -> Void

    public struct Payload: Hashable {
        public let contentType: String
        public let contentBlob: Data
        public let monthsFromNow: Int
    }

    @State private var text: String = ""
    @State private var months: Int = 12

    private let monthOptions = [3, 6, 12, 24]

    public init(
        experienceId: String,
        experienceTitle: String,
        onBury: @escaping (Payload) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.experienceId = experienceId
        self.experienceTitle = experienceTitle
        self.onBury = onBury
        self.onCancel = onCancel
    }

    public var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                Text("Leave a note here for future you.")
                    .font(.title3.weight(.semibold))
                    .foregroundColor(CT.fgPrimary)

                Text(experienceTitle)
                    .font(.footnote)
                    .foregroundColor(CT.fgMuted)

                TextEditor(text: $text)
                    .font(.body)
                    .padding(8)
                    .background(CT.chatInputBg)
                    .cornerRadius(12)
                    .frame(minHeight: 120)

                Picker("Surface in", selection: $months) {
                    ForEach(monthOptions, id: \.self) { m in
                        Text("\(m) months").tag(m)
                    }
                }
                .pickerStyle(.segmented)

                Spacer()

                Button(action: bury) {
                    Text("Bury")
                        .font(.callout.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(text.isEmpty ? CT.borderDefault : CT.capsuleGlow)
                        .foregroundColor(CT.fgPrimary)
                        .cornerRadius(20)
                }
                .disabled(text.isEmpty)
            }
            .padding(20)
            .navigationTitle("Time capsule")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onCancel)
                }
            }
        }
    }

    private func bury() {
        guard !text.isEmpty, let blob = text.data(using: .utf8) else { return }
        onBury(Payload(contentType: "text", contentBlob: blob, monthsFromNow: months))
    }
}

#Preview {
    CapsuleComposeView(
        experienceId: "demo",
        experienceTitle: "Kalare market alley",
        onBury: { _ in },
        onCancel: {}
    )
}
