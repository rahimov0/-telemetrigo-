import XCTest
@testable import KrovaCore

final class SuggestionTests: XCTestCase {
    func testSuggestions() {
        XCTAssertEqual(ActivityKind.walk.suggested(avgSpeed: 10 / 3.6), .run)
        XCTAssertNil(ActivityKind.walk.suggested(avgSpeed: 5 / 3.6))
        XCTAssertEqual(ActivityKind.run.suggested(avgSpeed: 4.5 / 3.6), .walk)
        XCTAssertNil(ActivityKind.run.suggested(avgSpeed: 10 / 3.6))
        XCTAssertEqual(ActivityKind.run.suggested(avgSpeed: 25 / 3.6), .bike)
        XCTAssertEqual(ActivityKind.bike.suggested(avgSpeed: 5 / 3.6), .walk)
        XCTAssertNil(ActivityKind.motorcycle.suggested(avgSpeed: 1))
    }
    func testGainAccumulator() {
        var g = GainAccumulator(threshold: 1)
        for x in [0, 0.3, 0.1, 2.0, 2.2, 1.0, 3.5] as [Double] { g.add(x) }
        XCTAssertEqual(g.gain, 2.0 + 2.5, accuracy: 0.001)
    }
}
