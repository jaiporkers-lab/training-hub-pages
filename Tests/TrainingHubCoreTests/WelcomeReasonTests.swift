import Foundation
import XCTest
@testable import TrainingHubCore

final class WelcomeReasonTests: XCTestCase {
    func testFirstLaunchAndUpdateIncludingMigrationFromTheOldTour() {
        let now = Date(timeIntervalSinceReferenceDate: 1_000)
        XCTAssertEqual(WelcomeReason.resolve(currentRelease: "0.8.3/17", previousRelease: nil,
                                             hasUsedEarlierVersion: false, lastUse: nil, now: now), .firstLaunch)
        XCTAssertEqual(WelcomeReason.resolve(currentRelease: "0.8.3/17", previousRelease: nil,
                                             hasUsedEarlierVersion: true, lastUse: nil, now: now), .updated)
        XCTAssertEqual(WelcomeReason.resolve(currentRelease: "0.8.3/17", previousRelease: "0.8.2/16",
                                             hasUsedEarlierVersion: true, lastUse: now, now: now), .updated)
    }

    func testReturnRequiresMoreThanThreeCalendarMonthsOnTheSameRelease() throws {
        let calendar = Calendar(identifier: .gregorian)
        let now = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 11, day: 10)))
        let cutoff = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 8, day: 10)))
        func welcome(lastUse: Date) -> WelcomeReason? {
            WelcomeReason.resolve(currentRelease: "0.8.3/17", previousRelease: "0.8.3/17",
                                  hasUsedEarlierVersion: true, lastUse: lastUse, now: now, calendar: calendar)
        }
        XCTAssertNil(welcome(lastUse: now))
        XCTAssertNil(welcome(lastUse: cutoff))
        XCTAssertEqual(welcome(lastUse: cutoff.addingTimeInterval(-1)), .returning)
    }
}
