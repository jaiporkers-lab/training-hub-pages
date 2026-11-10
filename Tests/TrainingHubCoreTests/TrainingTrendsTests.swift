import XCTest
import Foundation
@testable import TrainingHubCore

final class TrainingTrendsTests: XCTestCase {
    private var calendar: Calendar { var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(secondsFromGMT: 0)!; return c }
    private func date(_ day: Int, month: Int = 11, hour: Int = 12) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: month, day: day, hour: hour))!
    }
    private func legs() throws -> [Activity] {
        var items = try FITImporter.decode(DemoFIT.make(multisport: true), name: "Race").map(\.activity)
        for index in items.indices { items[index].isDemo = false; items[index].start = date(8).addingTimeInterval(Double(index * 1800)) }
        items[0].timer = 100; items[1].timer = nil; items[1].elapsed = 200
        items[0].distance = 1000; items[1].distance = nil
        return items
    }
    func testMultisportCountsOnceAndBreaksDownLegsWithoutDoubleCounting() throws {
        let items = try legs()
        let group = ActivityGroup(sessions: items)
        let report = TrainingTrends.make(activities: items + [group.summary, items[0]], now: date(8, hour: 15), calendar: calendar)
        XCTAssertEqual(report.current.activities, 1)
        XCTAssertEqual(report.current.seconds, 300)
        XCTAssertEqual(report.current.meters, 1000)
        XCTAssertEqual(report.current.missingDistances, 1)
        XCTAssertEqual(report.current.elapsedFallbacks, 1)
        XCTAssertEqual(report.sports.reduce(0) { $0 + $1.totals.seconds }, report.current.seconds)
        let bike = TrainingTrends.make(activities: items, sport: "cycling", now: date(8, hour: 15), calendar: calendar)
        XCTAssertEqual(bike.current.activities, 1); XCTAssertEqual(bike.current.seconds, 100)
    }
    func testAlignedPriorPeriodExcludesFutureAndDemoAndFillsEmptyWeeks() throws {
        var items = try legs()
        var previous = items[0]; previous.id = "previous"; previous.fileHash = "previous"; previous.start = date(11, month: 10, hour: 11)
        var tooLate = previous; tooLate.id = "late"; tooLate.fileHash = "late"; tooLate.start = date(11, month: 10, hour: 16)
        var demo = previous; demo.id = "demo"; demo.fileHash = "demo"; demo.start = date(7); demo.isDemo = true
        var future = previous; future.id = "future"; future.fileHash = "future"; future.start = date(9)
        items += [previous, tooLate, demo, future]
        let report = TrainingTrends.make(activities: items, now: date(8, hour: 15), calendar: calendar)
        XCTAssertEqual(report.weeks.count, 4)
        XCTAssertEqual(report.start, date(12, month: 10, hour: 0))
        XCTAssertEqual(report.previousEnd, date(11, month: 10, hour: 15))
        XCTAssertEqual(report.previous.activities, 1); XCTAssertEqual(report.current.activities, 1)
        XCTAssertEqual(report.weeks.reduce(0) { $0 + $1.current.activities }, 1)
        XCTAssertEqual(report.weeks.reduce(0) { $0 + $1.previous.activities }, 1)
        XCTAssertEqual(report.weeks.first?.current.activities, 0)
        XCTAssertEqual(TrainingTrends.make(activities: items, includeDemo: true, now: date(8, hour: 15), calendar: calendar).current.activities, 2)
    }
    func testCalendarAlignmentAcrossSydneyDaylightSaving() {
        var c = calendar; c.timeZone = TimeZone(identifier: "Australia/Sydney")!
        let now = c.date(from: DateComponents(year: 2026, month: 10, day: 7, hour: 14))!
        let report = TrainingTrends.make(activities: [], now: now, calendar: c)
        XCTAssertEqual(c.component(.weekday, from: report.start), 2)
        XCTAssertEqual(c.component(.weekday, from: report.previousEnd), c.component(.weekday, from: now))
        XCTAssertEqual(c.component(.hour, from: report.previousEnd), 14)
        XCTAssertEqual(report.current.activities, 0)
    }
}
