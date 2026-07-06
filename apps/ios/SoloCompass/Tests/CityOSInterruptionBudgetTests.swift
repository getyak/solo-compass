import XCTest
@testable import SoloCompass

/// City OS v2 §4.3: the ≤2/day proactive-surfacing budget — the quantified
/// "不做 engagement loop" anti-goal. Uses an isolated UserDefaults suite so
/// runs never bleed into the standard defaults (same pattern as
/// `LiveActivityService` budget tests).
final class CityOSInterruptionBudgetTests: XCTestCase {
    private var defaults: UserDefaults!
    private let suiteName = "CityOSInterruptionBudgetTests"
    private var calendar: Calendar { Calendar(identifier: .gregorian) }
    private let day1 = Date(timeIntervalSince1970: 1_780_000_000)

    override func setUp() {
        super.setUp()
        defaults = UserDefaults(suiteName: suiteName)
        defaults.removePersistentDomain(forName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    func testTwoPerDayCapEnforced() {
        XCTAssertTrue(CityOSInterruptionBudget.consumeProactive(now: day1, calendar: calendar, defaults: defaults))
        XCTAssertTrue(CityOSInterruptionBudget.consumeProactive(now: day1, calendar: calendar, defaults: defaults))
        XCTAssertFalse(CityOSInterruptionBudget.consumeProactive(now: day1, calendar: calendar, defaults: defaults),
                       "第 3 次主动浮现必须被预算拒绝")
    }

    func testRemainingTodayCountsDown() {
        XCTAssertEqual(CityOSInterruptionBudget.remainingToday(now: day1, calendar: calendar, defaults: defaults), 2)
        CityOSInterruptionBudget.consumeProactive(now: day1, calendar: calendar, defaults: defaults)
        XCTAssertEqual(CityOSInterruptionBudget.remainingToday(now: day1, calendar: calendar, defaults: defaults), 1)
    }

    func testDayRolloverResetsBudget() {
        CityOSInterruptionBudget.consumeProactive(now: day1, calendar: calendar, defaults: defaults)
        CityOSInterruptionBudget.consumeProactive(now: day1, calendar: calendar, defaults: defaults)
        let day2 = day1.addingTimeInterval(86_400)
        XCTAssertTrue(CityOSInterruptionBudget.consumeProactive(now: day2, calendar: calendar, defaults: defaults))
        XCTAssertEqual(CityOSInterruptionBudget.remainingToday(now: day2, calendar: calendar, defaults: defaults), 1)
    }

    func testFailedConsumeDoesNotSpendBudget() {
        CityOSInterruptionBudget.consumeProactive(now: day1, calendar: calendar, defaults: defaults)
        CityOSInterruptionBudget.consumeProactive(now: day1, calendar: calendar, defaults: defaults)
        CityOSInterruptionBudget.consumeProactive(now: day1, calendar: calendar, defaults: defaults) // rejected
        XCTAssertEqual(CityOSInterruptionBudget.remainingToday(now: day1, calendar: calendar, defaults: defaults), 0)
    }

    func testBudgetKeyIsDayScoped() {
        let key = CityOSInterruptionBudget.budgetKey(for: day1, calendar: calendar)
        XCTAssertTrue(key.hasPrefix("com.solocompass.cityos.proactive."))
        XCTAssertTrue(key.hasSuffix(".v1"))
    }
}
