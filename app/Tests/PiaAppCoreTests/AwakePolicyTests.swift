import XCTest
@testable import PiaAppCore

final class AwakePolicyTests: XCTestCase {
    func decide(works: Int = 1, battery: Int? = 80, onAC: Bool = false, thermal: Int = 0, stopped: Bool = false) -> AwakeDecision {
        AwakePolicy.decide(AwakeInputs(runningWorks: works, battery: battery, onAC: onAC, thermal: thermal, stoppedForBattery: stopped))
    }

    func testNoWorkNoHold() {
        let d = decide(works: 0)
        XCTAssertFalse(d.holdAwake)
        XCTAssertFalse(d.lowPower)
        XCTAssertEqual(d.reason, .idle)
    }

    func testRunningWorkHoldsOnBattery() {
        let d = decide(battery: 80)
        XCTAssertTrue(d.holdAwake)
        XCTAssertFalse(d.lowPower)
    }

    func testLowPowerAtForty() {
        XCTAssertTrue(decide(battery: 40).lowPower)
        XCTAssertFalse(decide(battery: 41).lowPower)
        XCTAssertFalse(decide(battery: 20, onAC: true).lowPower, "charging never needs low power for the battery")
    }

    func testBatteryStopAtTenAndStaysStoppedUntilRecovered() {
        let stop = decide(battery: 10)
        XCTAssertFalse(stop.holdAwake)
        XCTAssertEqual(stop.reason, .battery)
        XCTAssertTrue(stop.stoppedForBattery)
        // Still low and on battery: stays stopped even at 15 %.
        XCTAssertFalse(decide(battery: 15, stopped: true).holdAwake)
        // Recovered by 10 points: holds again.
        XCTAssertTrue(decide(battery: 20, stopped: true).holdAwake)
        // Plugged in: holds again at once.
        XCTAssertTrue(decide(battery: 11, onAC: true, stopped: true).holdAwake)
    }

    func testHeat() {
        XCTAssertTrue(decide(thermal: 2).lowPower, "serious heat → low power")
        let critical = decide(thermal: 3)
        XCTAssertFalse(critical.holdAwake)
        XCTAssertEqual(critical.reason, .heat)
    }

    func testDesktopMacWithoutBattery() {
        let d = decide(battery: nil, onAC: true)
        XCTAssertTrue(d.holdAwake)
        XCTAssertFalse(d.lowPower)
    }

    func testClaimParsing() {
        let url = URL(fileURLWithPath: "/tmp/x")
        XCTAssertEqual(Claim.parse(file: url, text: "/a/b/.pia/work/002\n4242\n")?.caffeinatePID, 4242)
        XCTAssertNil(Claim.parse(file: url, text: "/a/b\nnot-a-pid\n"))
        XCTAssertNil(Claim.parse(file: url, text: "\n"))
    }
}
