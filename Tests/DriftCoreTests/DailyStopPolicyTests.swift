import Foundation
import XCTest
@testable import DriftCore

final class DailyStopPolicyTests: XCTestCase {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    func testDisabledScheduleNeverTriggers() {
        var settings = DailyStopSettings.default
        settings.isEnabled = false

        XCTAssertNil(DailyStopPolicy().trigger(now: date(hour: 18), settings: settings, lastTrigger: nil, calendar: calendar))
    }

    func testUnselectedWeekdayNeverTriggers() {
        let settings = DailyStopSettings(isEnabled: true, hour: 18, minute: 0, weekdays: [2])

        XCTAssertNil(DailyStopPolicy().trigger(now: date(hour: 18), settings: settings, lastTrigger: nil, calendar: calendar))
    }

    func testEmptyWeekdaySelectionNeverTriggers() {
        let settings = DailyStopSettings(isEnabled: true, hour: 18, minute: 0, weekdays: [])

        XCTAssertNil(DailyStopPolicy().trigger(now: date(hour: 18), settings: settings, lastTrigger: nil, calendar: calendar))
    }

    func testTriggersAtConfiguredMinute() {
        let settings = DailyStopSettings(isEnabled: true, hour: 18, minute: 0, weekdays: [7])

        XCTAssertEqual(
            DailyStopPolicy().trigger(now: date(hour: 18), settings: settings, lastTrigger: nil, calendar: calendar),
            DailyStopTrigger(year: 2026, month: 8, day: 8)
        )
    }

    func testDoesNotTriggerBeforeConfiguredMinute() {
        let settings = DailyStopSettings(isEnabled: true, hour: 18, minute: 1, weekdays: [7])

        XCTAssertNil(DailyStopPolicy().trigger(now: date(hour: 18), settings: settings, lastTrigger: nil, calendar: calendar))
    }

    func testSameCalendarDateTriggersOnlyOnce() {
        let settings = DailyStopSettings(isEnabled: true, hour: 18, minute: 0, weekdays: [7])
        let trigger = DailyStopTrigger(year: 2026, month: 8, day: 8)

        XCTAssertNil(DailyStopPolicy().trigger(now: date(hour: 18), settings: settings, lastTrigger: trigger, calendar: calendar))
    }

    func testNextSelectedDateCanTriggerAgain() {
        let settings = DailyStopSettings(isEnabled: true, hour: 18, minute: 0, weekdays: [7, 1])
        let previous = DailyStopTrigger(year: 2026, month: 8, day: 8)
        let nextDay = calendar.date(from: DateComponents(year: 2026, month: 8, day: 9, hour: 18, minute: 0))!

        XCTAssertEqual(
            DailyStopPolicy().trigger(now: nextDay, settings: settings, lastTrigger: previous, calendar: calendar),
            DailyStopTrigger(year: 2026, month: 8, day: 9)
        )
    }

    private func date(hour: Int) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 8, day: 8, hour: hour, minute: 0))!
    }
}
