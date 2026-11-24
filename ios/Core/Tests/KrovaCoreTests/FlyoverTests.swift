import XCTest
@testable import KrovaCore

final class FlyoverTests: XCTestCase {
    private func line(north: Bool) -> [FlyoverTrack.Input] {
        (0..<50).map { i in
            let d = Double(i) * 0.0002
            return FlyoverTrack.Input(lat: 41 + (north ? d : 0), lon: 29 + (north ? 0 : d), t: Double(i) * 5, ele: Double(i))
        }
    }
    func testHeadingNorthAndEast() {
        let n = FlyoverTrack(points: line(north: true))!, e = FlyoverTrack(points: line(north: false))!
        XCTAssertEqual(n.state(at: 0.5).heading, 0, accuracy: 3)
        XCTAssertEqual(e.state(at: 0.5).heading, 90, accuracy: 3)
    }
    func testEndpointsAndDistance() {
        let t = FlyoverTrack(points: line(north: true))!
        XCTAssertEqual(t.state(at: 0).dist, 0, accuracy: 0.001)
        XCTAssertEqual(t.state(at: 1).dist, t.totalDistance, accuracy: 0.5)
        XCTAssertEqual(t.totalDistance, 49 * 0.0002 * 111_195, accuracy: 60)
        XCTAssertEqual(t.state(at: 1).time, 245, accuracy: 1)
    }
    func testSpeedAndPath() {
        let t = FlyoverTrack(points: line(north: true))!
        XCTAssertEqual(t.speed(at: 0.7), 0.0002 * 111_195 / 5, accuracy: 0.6)
        XCTAssertGreaterThan(t.path(upTo: 0.5).count, 100)
        XCTAssertNil(FlyoverTrack(points: [.init(lat: 1, lon: 1, t: 0)]))
    }
    func testGainAccumulates() {
        let t = FlyoverTrack(points: line(north: true))!
        XCTAssertGreaterThan(t.state(at: 1).gain, 40)
    }
}
