import XCTest
@testable import KrovaCore

final class CaloriesTests: XCTestCase {
    func testWalkingOneHour() {
        // 5 km/s yürüyüş, 70 kg, 1 saat: (3,8 - 1) * 70 = 196
        let k = Calories.active(kind: .walk, distance: 5000, movingTime: 3600, weightKg: 70)
        XCTAssertEqual(k ?? 0, 196, accuracy: 0.5)
    }
    func testRunningTenKmh() {
        // 10 km/s koşu, 70 kg, 1 saat: (10 - 1) * 70 = 630
        let k = Calories.active(kind: .run, distance: 10000, movingTime: 3600, weightKg: 70)
        XCTAssertEqual(k ?? 0, 630, accuracy: 0.5)
    }
    func testNoCaloriesForDriveKinds() {
        XCTAssertNil(Calories.active(kind: .motorcycle, distance: 50000, movingTime: 3600, weightKg: 80))
        XCTAssertNil(Calories.active(kind: .car, distance: 50000, movingTime: 3600, weightKg: 80))
    }
    func testNoCaloriesWithoutWeightOrTime() {
        XCTAssertNil(Calories.active(kind: .walk, distance: 5000, movingTime: 3600, weightKg: 0))
        XCTAssertNil(Calories.active(kind: .walk, distance: 20, movingTime: 10, weightKg: 70))
    }
    func testShortActivityValidity() {
        XCTAssertTrue(Validity.isTooShort(distance: 5, movingTime: 60))
        XCTAssertTrue(Validity.isTooShort(distance: 500, movingTime: 5))
        XCTAssertFalse(Validity.isTooShort(distance: 500, movingTime: 300))
    }
}
