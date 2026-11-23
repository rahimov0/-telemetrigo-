import XCTest
@testable import KrovaCore

final class DistanceTests: XCTestCase {
    func testStraightWalkWithinThreePercent() {
        XCTAssertLessThan(worstErrorPercent(.walk, Scenario()), 3)
    }
    func testWindingWalk() {
        XCTAssertLessThan(worstErrorPercent(.walk, Scenario(wiggle: 3.0)), 3)
    }
    func testSlowWalk() {
        XCTAssertLessThan(worstErrorPercent(.walk, Scenario(speed: 0.8)), 4)
    }
    func testWalkWithGpsJumpsIgnoresJumps() {
        XCTAssertLessThan(worstErrorPercent(.walk, Scenario(jumps: [100, 300, 450])), 3)
    }
    func testWalkThroughTunnelBridgesGap() {
        XCTAssertLessThan(worstErrorPercent(.walk, Scenario(tunnel: 200..<260)), 4)
    }
    func testWeakGps() {
        XCTAssertLessThan(worstErrorPercent(.walk, Scenario(hAcc: 20, corrSD: 6)), 3)
    }
    func testRunSteady() {
        XCTAssertLessThan(worstErrorPercent(.run, Scenario(speed: 3.0, wiggle: 2.0)), 5)
    }
    func testRunWithJumps() {
        XCTAssertLessThan(worstErrorPercent(.run, Scenario(speed: 3.0, jumps: [150, 400])), 5)
    }
    func testBike() {
        XCTAssertLessThan(worstErrorPercent(.bike, Scenario(speed: 6.0, hAcc: 6, wiggle: 2.0)), 5)
    }
    func testMotorcycleWithJump() {
        XCTAssertLessThan(worstErrorPercent(.motorcycle, Scenario(speed: 20.0, hAcc: 6, jumps: [200])), 3)
    }
    func testStandingStillGivesNoPhantomDistance() {
        for s in 0..<12 {
            let r = runScenario(.walk, Scenario(seconds: 300, speed: 0), seed: UInt64(s) &* 131 &+ 7)
            XCTAssertLessThan(r.engine.distance, 5, "tohum \(s)")
            XCTAssertLessThan(r.engine.movingTime, 10, "tohum \(s)")
        }
    }
    func testJumpAloneNeverAddsDistance() {
        // aynı yerde dururken bir ölçüm 80 m sıçrasa bile mesafe artmaz
        var e = DistanceEngine(kind: .run)
        for t in 0..<20 { e.add(Fix(t: Double(t), lat: 41, lon: 29, hAcc: 5, speed: 0)) }
        e.add(Fix(t: 20, lat: 41.0007, lon: 29, hAcc: 5, speed: 0.1))
        for t in 21..<40 { e.add(Fix(t: Double(t), lat: 41, lon: 29, hAcc: 5, speed: 0)) }
        XCTAssertEqual(e.distance, 0, accuracy: 0.001)
    }
    func testBadAccuracyFixesAreRejected() {
        var e = DistanceEngine(kind: .walk)
        e.add(Fix(t: 0, lat: 41, lon: 29, hAcc: 5, speed: 1.4))
        e.add(Fix(t: 1, lat: 41.001, lon: 29, hAcc: 80, speed: 20))
        XCTAssertEqual(e.rejectedFixes, 1)
        XCTAssertEqual(e.distance, 0, accuracy: 0.001)
    }
    func testBreakSegmentDoesNotCountGapBetweenPauseAndResume() {
        var e = DistanceEngine(kind: .run)
        for t in 0..<10 { e.add(Fix(t: Double(t), lat: 41 + Double(t) * 3.0 / 111_320, lon: 29, hAcc: 5, speed: 3.0)) }
        let before = e.distance
        e.breakSegment()
        // duraklatma sırasında 500 m uzağa gidildi; yeni parça orada başlar
        for t in 100..<110 { e.add(Fix(t: Double(t), lat: 41.005 + Double(t - 100) * 3.0 / 111_320, lon: 29, hAcc: 5, speed: 3.0)) }
        XCTAssertEqual(e.distance - before, 27, accuracy: 3)   // yalnızca yeni parçadaki 9 aralık
    }
    func testMovingTimeIgnoresStopped() {
        var e = DistanceEngine(kind: .run)
        for t in 0..<30 { e.add(Fix(t: Double(t), lat: 41 + Double(t) * 3.0 / 111_320, lon: 29, hAcc: 5, speed: 3.0)) }
        let la = 41 + 30.0 * 3.0 / 111_320
        for t in 30..<90 { e.add(Fix(t: Double(t), lat: la, lon: 29, hAcc: 5, speed: 0.05)) }
        XCTAssertEqual(e.movingTime, 29, accuracy: 2)
    }
    func testMaxSpeedIgnoresImplausible() {
        var e = DistanceEngine(kind: .walk)
        e.add(Fix(t: 0, lat: 41, lon: 29, hAcc: 5, speed: 1.4))
        e.add(Fix(t: 1, lat: 41.00001, lon: 29, hAcc: 5, speed: 12.0))
        e.add(Fix(t: 2, lat: 41.00002, lon: 29, hAcc: 5, speed: 1.6))
        XCTAssertEqual(e.maxSpeed, 1.6, accuracy: 0.001)
    }
}
