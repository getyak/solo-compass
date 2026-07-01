import SwiftUI

/// P3.3 #331: monthly insight card. Consumed by ArchiveView and by the
/// month-start notification's deep-link.
public struct InsightCardView: View {

    public let data: MonthlyInsightData
    public let onShare: () -> Void

    public init(data: MonthlyInsightData, onShare: @escaping () -> Void) {
        self.data = data
        self.onShare = onShare
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text(monthLabel)
                    .font(.caption.weight(.semibold))
                    .tracking(1.4)
                    .foregroundColor(CT.omenGold)
                Spacer()
                Button(action: onShare) {
                    Image(systemName: "square.and.arrow.up")
                        .foregroundColor(CT.fgMuted)
                }
            }

            HStack(spacing: 16) {
                stat(value: "\(data.visitCount)", label: "visits")
                stat(value: "\(data.uniqueExperienceCount)", label: "unique")
                if data.uniqueCityCount > 1 {
                    stat(value: "\(data.uniqueCityCount)", label: "cities")
                }
            }

            ForEach(data.insights, id: \.self) { line in
                HStack(alignment: .top, spacing: 6) {
                    Text("·")
                        .foregroundColor(CT.omenGold)
                    Text(line)
                        .font(.callout)
                        .foregroundColor(CT.fgPrimary)
                }
            }
        }
        .padding(20)
        .background(CT.surfaceWhite)
        .cornerRadius(20)
        .shadow(color: .black.opacity(0.06), radius: 10, y: 4)
        .padding(.horizontal, 20)
    }

    @ViewBuilder
    private func stat(value: String, label: String) -> some View {
        VStack(alignment: .leading) {
            Text(value)
                .font(.system(size: 24, weight: .bold, design: .rounded))
                .foregroundColor(CT.fgPrimary)
            Text(label)
                .font(.caption)
                .foregroundColor(CT.fgMuted)
        }
    }

    private var monthLabel: String {
        let f = DateFormatter()
        f.dateFormat = "MMMM yyyy"
        return f.string(from: data.monthStart).uppercased()
    }
}

#Preview {
    InsightCardView(
        data: .init(
            monthStart: Date(),
            visitCount: 24,
            uniqueExperienceCount: 18,
            uniqueCityCount: 2,
            topCategory: "coffee",
            dominantHourBand: "afternoon",
            insights: [
                "You logged 24 places this month.",
                "Your gravity: coffee.",
                "Your time of day was afternoon.",
            ],
            createdAt: Date()
        ),
        onShare: {}
    )
}
