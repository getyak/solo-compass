import SwiftUI

/// Custom marker icon, 44x44 tap target. The visual changes with marker state;
/// the surrounding circle is always the category color, plus state-specific
/// adornments (gold glow, checkmark, heart, countdown, footprint).
public struct MarkerIconView: View {
    let category: ExperienceCategory
    let state: ExperienceMarkerState

    @State private var pulse = false

    public init(category: ExperienceCategory, state: ExperienceMarkerState) {
        self.category = category
        self.state = state
    }

    public var body: some View {
        ZStack {
            // Pulse ring for "best now"
            if case .bestNow = state {
                Circle()
                    .fill(Color(red: 0xD4/255, green: 0xA8/255, blue: 0x43/255).opacity(0.4))
                    .frame(width: 56, height: 56)
                    .scaleEffect(pulse ? 1.2 : 0.9)
                    .opacity(pulse ? 0.0 : 0.7)
                    .animation(.easeOut(duration: 1.5).repeatForever(autoreverses: false), value: pulse)
                    .onAppear { pulse = true }
            }

            Circle()
                .fill(fillColor)
                .frame(width: 36, height: 36)
                .overlay(
                    Circle().stroke(.white, lineWidth: 2)
                )
                .shadow(color: shadowColor, radius: shadowRadius)
                .opacity(opacity)

            Image(systemName: category.symbol)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white)
                .opacity(opacity)

            adornment
        }
        .frame(width: 44, height: 44)
        .accessibilityLabel(Text(accessibilityLabel))
    }

    private var fillColor: Color {
        switch state {
        case .bestNow: return Color(red: 0xD4/255, green: 0xA8/255, blue: 0x43/255)
        case .completed, .footprinted: return category.color
        default: return category.color
        }
    }

    private var shadowColor: Color {
        switch state {
        case .bestNow: return Color(red: 0xD4/255, green: 0xA8/255, blue: 0x43/255).opacity(0.6)
        default: return .black.opacity(0.2)
        }
    }

    private var shadowRadius: CGFloat {
        switch state {
        case .bestNow: return 8
        default: return 3
        }
    }

    private var opacity: Double {
        switch state {
        case .completed: return 0.45
        default: return 1.0
        }
    }

    @ViewBuilder
    private var adornment: some View {
        switch state {
        case .completed:
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(.white, .green)
                .offset(x: 12, y: 12)
        case .favorited:
            Image(systemName: "heart.fill")
                .font(.system(size: 12))
                .foregroundStyle(.red)
                .padding(3)
                .background(Circle().fill(.white))
                .offset(x: 12, y: -12)
        case .upcoming(let minutes):
            Text("\(minutes)")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 18, height: 18)
                .background(Circle().fill(Color.black.opacity(0.85)))
                .offset(x: 12, y: -12)
        case .footprinted:
            Image(systemName: "figure.walk")
                .font(.system(size: 9))
                .foregroundStyle(.white)
                .padding(3)
                .background(Circle().fill(Color.gray))
                .offset(x: 12, y: 12)
        case .bestNow, .default:
            EmptyView()
        }
    }

    private var accessibilityLabel: String {
        let categoryName = category.localizedTitle
        switch state {
        case .bestNow:
            return "\(categoryName), \(NSLocalizedString("marker.a11y.bestNow", comment: ""))"
        case .completed:
            return "\(categoryName), \(NSLocalizedString("marker.a11y.completed", comment: ""))"
        case .favorited:
            return "\(categoryName), \(NSLocalizedString("marker.a11y.favorited", comment: ""))"
        case .upcoming(let m):
            let fmt = NSLocalizedString("marker.a11y.upcoming", comment: "starts in %d minutes")
            return "\(categoryName), \(String(format: fmt, m))"
        case .footprinted:
            return "\(categoryName), \(NSLocalizedString("marker.a11y.footprinted", comment: ""))"
        case .default:
            return categoryName
        }
    }
}

#Preview {
    let states: [(String, ExperienceMarkerState)] = [
        ("default", .default),
        ("bestNow", .bestNow),
        ("completed", .completed),
        ("favorited", .favorited),
        ("upcoming 47", .upcoming(minutes: 47)),
        ("footprinted", .footprinted),
    ]
    return ScrollView {
        VStack(spacing: 16) {
            ForEach(states, id: \.0) { name, state in
                HStack(spacing: 16) {
                    Text(name).frame(width: 120, alignment: .leading)
                    ForEach(ExperienceCategory.allCases) { cat in
                        MarkerIconView(category: cat, state: state)
                    }
                }
            }
        }
        .padding()
    }
    .background(Color(red: 0xF5/255, green: 0xF0/255, blue: 0xE8/255))
}
