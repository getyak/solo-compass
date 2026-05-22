import Foundation
import SwiftUI

// MARK: - Style

/// Supported share card aspect ratios / social-platform targets.
public enum ShareCardStyle: String, CaseIterable, Identifiable {
    /// 1080×1920 — IG Story / Xiaohongshu portrait. Hero + highlights + score.
    case xiaohongshuPortrait
    /// 1200×628 — Twitter/X summary_large_image / LinkedIn / generic OG.
    case twitterLandscape
    /// 1080×1080 — Instagram Feed / WeChat groups.
    case instagramSquare
    /// 1080×1920 — emoji + gradient, no hero image. Default fallback when no photo.
    case minimalText

    public var id: String { rawValue }

    /// Target pixel size for export.
    public var pixelSize: CGSize {
        switch self {
        case .xiaohongshuPortrait, .minimalText: return CGSize(width: 1080, height: 1920)
        case .twitterLandscape:                  return CGSize(width: 1200, height: 628)
        case .instagramSquare:                   return CGSize(width: 1080, height: 1080)
        }
    }

    /// SwiftUI render size in points. ImageRenderer multiplies by `scale` for pixel output.
    /// Render at /2 to keep on-screen text rendering correct, then scale up.
    public var renderSize: CGSize {
        CGSize(width: pixelSize.width / 2, height: pixelSize.height / 2)
    }

    /// Effective `scale` to pass to ImageRenderer so output matches `pixelSize`.
    public var renderScale: CGFloat { 2.0 }

    public var localizedTitle: String {
        NSLocalizedString("share.style.\(rawValue)", comment: "Share card style label")
    }
}

// MARK: - Payload

/// Pure-data input to a share card. Decoupled from `Experience` so we can preview / test
/// without seed data, and so future non-Experience sources (e.g. itineraries) can reuse cards.
public struct ShareCardPayload: Hashable {
    public let title: String
    public let category: ExperienceCategory
    public let oneLiner: String
    public let soloScore: Double            // 0–10 scale (matches Experience.soloScore.overall)
    public let highlights: [String]         // 2–4 short bullets
    public let placeLabel: String?          // "Tokyo" / "Bali" / nil
    public let coordinate: Coordinate?
    public let brandHandle: String

    public struct Coordinate: Hashable {
        public let lon: Double
        public let lat: Double
        public init(lon: Double, lat: Double) { self.lon = lon; self.lat = lat }
    }

    public init(
        title: String,
        category: ExperienceCategory,
        oneLiner: String,
        soloScore: Double,
        highlights: [String],
        placeLabel: String?,
        coordinate: Coordinate?,
        brandHandle: String = "solocompass.app"
    ) {
        self.title = title
        self.category = category
        self.oneLiner = oneLiner
        self.soloScore = soloScore
        self.highlights = highlights
        self.placeLabel = placeLabel
        self.coordinate = coordinate
        self.brandHandle = brandHandle
    }

    /// Score on the 0–100 scale used by the big card number.
    public var score100: Int { Int((max(0, min(10, soloScore)) * 10).rounded()) }
}

public extension ShareCardPayload {
    /// Builds a card payload from an `Experience`. Highlights = first 3 `howTo` steps (trimmed),
    /// falling back to `whyItMatters` split on sentences.
    init(experience: Experience) {
        let hl: [String] = {
            let stepTexts = experience.howTo
                .sorted(by: { $0.order < $1.order })
                .prefix(3)
                .map { ShareCardPayload.trimBullet($0.text) }
                .filter { !$0.isEmpty }
            if !stepTexts.isEmpty { return stepTexts }
            return experience.whyItMatters
                .split(whereSeparator: { ".。!?！？\n".contains($0) })
                .prefix(3)
                .map { ShareCardPayload.trimBullet(String($0)) }
                .filter { !$0.isEmpty }
        }()

        let placeLabel: String? = experience.location.placeNameLocal
            ?? experience.location.placeNameRomanized
            ?? experience.location.addressHint

        let coord: Coordinate? = {
            guard experience.location.coordinates.count >= 2 else { return nil }
            return Coordinate(
                lon: experience.location.coordinates[0],
                lat: experience.location.coordinates[1]
            )
        }()

        self.init(
            title: experience.title,
            category: experience.category,
            oneLiner: experience.oneLiner,
            soloScore: experience.soloScore.overall,
            highlights: hl,
            placeLabel: placeLabel,
            coordinate: coord
        )
    }

    private static func trimBullet(_ raw: String) -> String {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.count > 60 {
            let idx = s.index(s.startIndex, offsetBy: 57)
            s = String(s[..<idx]) + "…"
        }
        return s
    }
}

// MARK: - Category visual mapping

/// Maps each `ExperienceCategory` to (emoji, gradient pair). The research report
/// recommends a same-family two-color 135° gradient and a category-semantic emoji.
public enum CategoryVisual {
    public static func emoji(for category: ExperienceCategory) -> String {
        switch category {
        case .culture:   return "🏯"
        case .nature:    return "🌿"
        case .food:      return "🍜"
        case .coffee:    return "☕"
        case .work:      return "💻"
        case .wellness:  return "🧘"
        case .nightlife: return "🌙"
        case .hidden:    return "✨"
        }
    }

    public static func gradient(for category: ExperienceCategory) -> LinearGradient {
        let (a, b) = colorPair(for: category)
        return LinearGradient(
            colors: [a, b],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    /// Exposed for tests — every category must yield a non-default pair.
    public static func colorPair(for category: ExperienceCategory) -> (Color, Color) {
        switch category {
        case .food:      return (Color(red: 1.00, green: 0.42, blue: 0.42), Color(red: 0.77, green: 0.27, blue: 0.41))
        case .coffee:    return (Color(red: 0.85, green: 0.62, blue: 0.40), Color(red: 0.45, green: 0.27, blue: 0.18))
        case .culture:   return (Color(red: 0.96, green: 0.62, blue: 0.32), Color(red: 0.72, green: 0.27, blue: 0.25))
        case .nature:    return (Color(red: 0.27, green: 0.76, blue: 0.64), Color(red: 0.16, green: 0.42, blue: 0.55))
        case .work:      return (Color(red: 0.36, green: 0.55, blue: 0.92), Color(red: 0.20, green: 0.27, blue: 0.55))
        case .wellness:  return (Color(red: 0.55, green: 0.83, blue: 0.78), Color(red: 0.28, green: 0.50, blue: 0.55))
        case .nightlife: return (Color(red: 0.42, green: 0.31, blue: 0.78), Color(red: 0.20, green: 0.13, blue: 0.42))
        case .hidden:    return (Color(red: 0.65, green: 0.65, blue: 0.78), Color(red: 0.30, green: 0.30, blue: 0.42))
        }
    }
}
