import SwiftUI

/// Small reusable pieces shared across the Live Activity layouts. Direct ports
/// of the corresponding bits in `island_notif.css` (.wave / .av-stack /
/// .exp-stops / .exp-pill / .compile-dots).

// MARK: - Waveform (录制语音)

/// Amplitude bars for the recording scenario. `samples` are 0–1 magnitudes
/// (newest last). Mirrors `.wave` — amber-red bars, rounded, min 14% height so a
/// silent moment still reads as "live".
struct IslandWaveform: View {
    let samples: [Double]
    var barCount: Int = 22
    var height: CGFloat = 30
    var tint: Color = IP.rec

    var body: some View {
        GeometryReader { geo in
            let bars = normalized()
            let gap: CGFloat = 3
            let barW = max(2, (geo.size.width - gap * CGFloat(bars.count - 1)) / CGFloat(bars.count))
            HStack(alignment: .center, spacing: gap) {
                ForEach(Array(bars.enumerated()), id: \.offset) { _, v in
                    Capsule(style: .continuous)
                        .fill(tint.opacity(0.55 + 0.45 * v))
                        .frame(width: barW, height: max(height * 0.14, height * CGFloat(v)))
                }
            }
            .frame(width: geo.size.width, height: geo.size.height, alignment: .center)
        }
        .frame(height: height)
    }

    /// Resample / pad the incoming samples to a fixed bar count so the bar width
    /// stays stable as the rolling window fills.
    private func normalized() -> [Double] {
        guard !samples.isEmpty else { return Array(repeating: 0.12, count: barCount) }
        if samples.count == barCount { return samples }
        if samples.count > barCount {
            return Array(samples.suffix(barCount))
        }
        // Left-pad with low bars so new audio scrolls in from the right.
        return Array(repeating: 0.12, count: barCount - samples.count) + samples
    }
}

// MARK: - Avatar stack (出发倒计时 members)

/// Overlapping initial-circles, capped, with a black ring like the spec
/// (`.av-stack .av { box-shadow: 0 0 0 2px #000 }`).
struct IslandAvatarStack: View {
    let initials: [String]
    var size: CGFloat = 26
    var cap: Int = 3

    private static let palette: [Color] = [IP.avatarAmber, IP.accent, IP.avatarBlue]

    var body: some View {
        HStack(spacing: -size * 0.31) {
            ForEach(Array(initials.prefix(cap).enumerated()), id: \.offset) { idx, name in
                Text(name)
                    .font(.islandDisplay(size * 0.46, .semibold))
                    .foregroundStyle(IP.cream)
                    .frame(width: size, height: size)
                    .background(Circle().fill(Self.palette[idx % Self.palette.count]))
                    .overlay(Circle().stroke(.black, lineWidth: 2))
            }
        }
    }
}

// MARK: - Stop progress (路线进度)

/// The dotted progress rail under the route's next-stop block
/// (`.exp-stops` — done dots gold, the current dot a haloed cream).
struct IslandStopProgress: View {
    let current: Int   // 1-based current stop
    let total: Int

    var body: some View {
        HStack(spacing: 0) {
            ForEach(0..<safeTotal, id: \.self) { i in
                dot(for: i)
                if i < safeTotal - 1 {
                    Rectangle()
                        .fill(i < current - 1 ? IP.sunGold : IP.cream(0.16))
                        .frame(height: 2)
                }
            }
        }
        .frame(height: 11)
    }

    private var safeTotal: Int { Swift.max(total, 1) }

    @ViewBuilder private func dot(for i: Int) -> some View {
        let stop = i + 1
        if stop < current {
            Circle().fill(IP.sunGold).frame(width: 11, height: 11)
        } else if stop == current {
            Circle().fill(IP.sunGoldSoft).frame(width: 11, height: 11)
                .overlay(Circle().stroke(IP.sunGold.opacity(0.25), lineWidth: 4))
        } else {
            Circle().fill(IP.cream(0.2)).frame(width: 11, height: 11)
        }
    }
}

// MARK: - Pill (status / count chip)

/// The gold mono pill in expanded headers (`.exp-pill`).
struct IslandPill: View {
    let text: String
    var tint: Color = IP.sunGoldSoft
    var fill: Color = IP.goldPill
    var stroke: Color = IP.goldBorder

    var body: some View {
        Text(text)
            .font(.islandMono(11, .medium))
            .foregroundStyle(tint)
            .padding(.horizontal, 9)
            .padding(.vertical, 3)
            .background(Capsule().fill(fill))
            .overlay(Capsule().stroke(stroke, lineWidth: 1))
    }
}

// MARK: - Compile dots (AI 编排)

/// The three gold dots used as the compact trailing accessory for the compile
/// scenario (`.compile-dots`). Static here (Live Activities can't run keyframe
/// loops), so it reads as a settled three-dot glyph.
struct IslandCompileDots: View {
    var body: some View {
        HStack(spacing: 3) {
            ForEach(0..<3, id: \.self) { i in
                Circle()
                    .fill(IP.sunGold.opacity(i == 1 ? 1 : 0.5))
                    .frame(width: 4, height: 4)
            }
        }
    }
}

// MARK: - Icon tile

/// Rounded amber-tinted square that hosts an SF Symbol in expanded headers
/// (`.exp-ic`). `recording` swaps to the red tint.
struct IslandIconTile: View {
    let systemName: String
    var fill: Color = IP.goldTile
    var tint: Color = IP.sunGold
    var size: CGFloat = 30

    var body: some View {
        RoundedRectangle(cornerRadius: 9, style: .continuous)
            .fill(fill)
            .frame(width: size, height: size)
            .overlay(
                Image(systemName: systemName)
                    .font(.system(size: size * 0.5, weight: .semibold))
                    .foregroundStyle(tint)
            )
    }
}
