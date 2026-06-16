import XCTest
import SwiftUI
@testable import SoloCompass

final class SoloScoreBadgeScaleTest: XCTestCase {

    @MainActor
    func testCompactBadgeRendersWithScale() throws {
        let scores: [(Double, String)] = [
            (8.7, "excellent"),
            (5.2, "mid"),
            (3.1, "caution"),
        ]

        for (overall, label) in scores {
            let score = SoloScore(
                overall: overall,
                breakdown: .init(
                    seatingFriendly: overall,
                    soloPatronRatio: overall,
                    staffPressure: overall,
                    soloPortioning: overall,
                    ambianceFit: overall,
                    safety: overall
                ),
                basedOnCount: 10
            )
            let badge = SoloScoreBadge(score: score, style: .compact)
                .frame(width: 200, height: 50)

            let renderer = ImageRenderer(content: badge)
            renderer.scale = 2.0
            let image = renderer.uiImage
            XCTAssertNotNil(image, "Compact badge should render for \(label) score \(overall)")

            if let data = image?.pngData() {
                try data.write(to: URL(fileURLWithPath: "/tmp/solo_badge_compact_\(label).png"))
            }
        }
    }

    @MainActor
    func testFullBadgeRendersWithScale() throws {
        let score = SoloScore(
            overall: 7.8,
            breakdown: .init(
                seatingFriendly: 8,
                soloPatronRatio: 7,
                staffPressure: 9,
                soloPortioning: 6,
                ambianceFit: 8,
                safety: 9
            ),
            hint: "Corner seats are ideal.",
            basedOnCount: 11
        )
        let badge = SoloScoreBadge(score: score, style: .full)
            .frame(width: 350, height: 100)

        let renderer = ImageRenderer(content: badge)
        renderer.scale = 2.0
        let image = renderer.uiImage
        XCTAssertNotNil(image, "Full badge should render with /10 scale")

        if let data = image?.pngData() {
            try data.write(to: URL(fileURLWithPath: "/tmp/solo_badge_full.png"))
        }
    }

    func testScoreColorGradient() {
        let low = SoloScore(
            overall: 2.0,
            breakdown: .init(seatingFriendly: 2, soloPatronRatio: 2, staffPressure: 2, soloPortioning: 2, ambianceFit: 2, safety: 2),
            basedOnCount: 5
        )
        let mid = SoloScore(
            overall: 5.0,
            breakdown: .init(seatingFriendly: 5, soloPatronRatio: 5, staffPressure: 5, soloPortioning: 5, ambianceFit: 5, safety: 5),
            basedOnCount: 5
        )
        let high = SoloScore(
            overall: 9.0,
            breakdown: .init(seatingFriendly: 9, soloPatronRatio: 9, staffPressure: 9, soloPortioning: 9, ambianceFit: 9, safety: 9),
            basedOnCount: 5
        )

        let lowColor = low.scoreColor
        let midColor = mid.scoreColor
        let highColor = high.scoreColor

        XCTAssertNotEqual(
            lowColor.description, highColor.description,
            "Low and high scores should have different colors"
        )
        XCTAssertNotEqual(
            lowColor.description, midColor.description,
            "Low and mid scores should have different colors"
        )
    }
}
