import SwiftUI

/// P3.0 #303: "My City Codex" — every unlocked omen card, gridded.
public struct CityCodexView: View {

    public struct Entry: Hashable, Identifiable {
        public let id: Date
        public let cityCode: String
        public let line: String
        public let completed: Bool

        public init(id: Date, cityCode: String, line: String, completed: Bool) {
            self.id = id
            self.cityCode = cityCode
            self.line = line
            self.completed = completed
        }
    }

    public let entries: [Entry]
    public let isPro: Bool
    public let onUpsell: () -> Void

    private let columns = [GridItem(.adaptive(minimum: 110), spacing: 12)]

    public init(entries: [Entry], isPro: Bool, onUpsell: @escaping () -> Void) {
        self.entries = entries
        self.isPro = isPro
        self.onUpsell = onUpsell
    }

    public var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(entries) { entry in
                    tile(for: entry)
                }
            }
            .padding(20)

            if !isPro {
                upsellBar
                    .padding(.horizontal, 20)
                    .padding(.bottom, 20)
            }
        }
        .background(CT.pageAdaptive)
        .navigationTitle("City Codex")
    }

    @ViewBuilder
    private func tile(for entry: Entry) -> some View {
        VStack(spacing: 6) {
            Text(entry.cityCode.uppercased())
                .font(.caption.weight(.semibold))
                .tracking(1.2)
                .foregroundColor(CT.omenGold)
            Text(entry.line)
                .font(.footnote)
                .foregroundColor(CT.fgPrimary)
                .multilineTextAlignment(.center)
                .lineLimit(3)
            Text(entry.id, format: .dateTime.day().month(.abbreviated))
                .font(.caption2)
                .foregroundColor(CT.fgSubtle)
        }
        .padding(10)
        .frame(minHeight: 108)
        .background(entry.completed ? CT.accentSoft : CT.surfaceSunken)
        .cornerRadius(14)
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(entry.completed ? CT.omenGold : CT.borderSubtle, lineWidth: 1)
        )
        .opacity(entry.completed ? 1.0 : 0.55)
    }

    private var upsellBar: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Free tier shows the current month.")
                    .font(.footnote.weight(.semibold))
                    .foregroundColor(CT.fgPrimary)
                Text("Pro reveals your entire codex.")
                    .font(.caption)
                    .foregroundColor(CT.fgMuted)
            }
            Spacer()
            Button("Unlock", action: onUpsell)
                .font(.callout.weight(.semibold))
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(CT.omenGold)
                .foregroundColor(.white)
                .cornerRadius(16)
        }
        .padding(14)
        .background(CT.surfaceWhite)
        .cornerRadius(14)
    }
}

#Preview {
    CityCodexView(
        entries: [
            .init(id: Date().addingTimeInterval(-86400), cityCode: "cmi", line: "Sit where the light is thin.", completed: true),
            .init(id: Date(), cityCode: "cmi", line: "Order the second cheapest coffee.", completed: false),
        ],
        isPro: false,
        onUpsell: {}
    )
}
