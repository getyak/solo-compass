import XCTest
import Foundation
@testable import SoloCompass

/// Nomad OS B1-d: `TodaySealReceipt` shows a capsule buried *yesterday*
/// (design §2 ④ option a). These pin the day-boundary selection so the receipt
/// never surfaces today's fresh seal or an older one, and picks the latest when
/// several were buried yesterday.
final class TodaySealReceiptTests: XCTestCase {

    private let cal = Calendar.current

    private func capsule(createdAt: Date) -> TimeCapsule {
        TimeCapsule(
            experienceId: "exp_test",
            createdAt: createdAt,
            scheduledFor: cal.date(byAdding: .month, value: 6, to: createdAt)!,
            contentType: "text",
            contentBlob: Data()
        )
    }

    /// A capsule created yesterday qualifies.
    func testPicksYesterdayCapsule() {
        let now = Date()
        let yesterdayNoon = cal.date(byAdding: .day, value: -1, to: now)!
        let result = TodaySealReceipt.yesterdayCapsule(
            from: [capsule(createdAt: yesterdayNoon)], now: now
        )
        XCTAssertNotNil(result, "a capsule buried yesterday should surface")
    }

    /// Today's fresh capsule must NOT surface as "yesterday's".
    func testExcludesTodayCapsule() {
        let now = cal.date(bySettingHour: 14, minute: 0, second: 0, of: Date())!
        let earlierToday = cal.date(bySettingHour: 9, minute: 0, second: 0, of: now)!
        let result = TodaySealReceipt.yesterdayCapsule(
            from: [capsule(createdAt: earlierToday)], now: now
        )
        XCTAssertNil(result, "today's capsule is not yesterday's receipt")
    }

    /// A capsule from two days ago is outside the yesterday window.
    func testExcludesOlderCapsule() {
        let now = Date()
        let twoDaysAgo = cal.date(byAdding: .day, value: -2, to: now)!
        let result = TodaySealReceipt.yesterdayCapsule(
            from: [capsule(createdAt: twoDaysAgo)], now: now
        )
        XCTAssertNil(result, "a capsule older than yesterday must not surface")
    }

    /// With several buried yesterday, the most recent one wins.
    func testPicksLatestAmongYesterday() {
        let now = Date()
        let yStart = cal.startOfDay(for: cal.date(byAdding: .day, value: -1, to: now)!)
        let morning = cal.date(byAdding: .hour, value: 8, to: yStart)!
        let evening = cal.date(byAdding: .hour, value: 20, to: yStart)!
        let result = TodaySealReceipt.yesterdayCapsule(
            from: [capsule(createdAt: morning), capsule(createdAt: evening)], now: now
        )
        XCTAssertEqual(result?.createdAt, evening, "latest capsule of yesterday wins")
    }
}
