import XCTest
@testable import KrovaCore

final class KindRulesTests: XCTestCase {
    func testDriveKindsHaveNoCaloriesGoalsOrHealth() {
        for k in [ActivityKind.motorcycle, .car] {
            XCTAssertEqual(k.group, .drive)
            XCTAssertFalse(k.countsCalories)
            XCTAssertFalse(k.countsTowardGoals)
            XCTAssertFalse(k.writesToHealth)
            XCTAssertTrue(k.supportsAutoPause)
            XCTAssertFalse(k.autoPauseDefault)
            XCTAssertFalse(k.showsPace)
        }
    }
    func testSportKindsCountEverything() {
        for k in [ActivityKind.walk, .run, .hike, .bike] {
            XCTAssertEqual(k.group, .sport)
            XCTAssertTrue(k.countsCalories)
            XCTAssertTrue(k.countsTowardGoals)
            XCTAssertTrue(k.writesToHealth)
            XCTAssertTrue(k.supportsAutoPause)
        }
    }
    func testPaceVsSpeedDisplay() {
        XCTAssertTrue(ActivityKind.walk.showsPace)
        XCTAssertTrue(ActivityKind.run.showsPace)
        XCTAssertTrue(ActivityKind.hike.showsPace)
        XCTAssertFalse(ActivityKind.bike.showsPace)
    }
    func testWalkingAutoPauseOffByDefault() {
        XCTAssertFalse(ActivityKind.walk.autoPauseDefault)
        XCTAssertTrue(ActivityKind.run.autoPauseDefault)
    }
    func testPlausibleSpeedsAreOrdered() {
        XCTAssertLessThan(ActivityKind.walk.maxPlausibleSpeed, ActivityKind.run.maxPlausibleSpeed)
        XCTAssertLessThan(ActivityKind.run.maxPlausibleSpeed, ActivityKind.bike.maxPlausibleSpeed)
        XCTAssertLessThan(ActivityKind.bike.maxPlausibleSpeed, ActivityKind.motorcycle.maxPlausibleSpeed)
    }
}
