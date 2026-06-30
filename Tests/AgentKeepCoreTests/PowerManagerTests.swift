import XCTest
@testable import AgentKeepCore

final class PowerManagerTests: XCTestCase {
    func testParsesSleepDisabledWhenEnabled() {
        let output = """
        System-wide power settings:
         SleepDisabled\t\t1
        Currently in use:
         sleep                1
        """

        XCTAssertEqual(PowerManager.parseSleepDisabledValue(from: output), true)
    }

    func testParsesSleepDisabledWhenDisabled() {
        let output = """
        System-wide power settings:
         SleepDisabled\t\t0
        Currently in use:
         sleep                1
        """

        XCTAssertEqual(PowerManager.parseSleepDisabledValue(from: output), false)
    }

    func testParsesLegacyDisablesleepKey() {
        let output = """
        Currently in use:
         disablesleep         1
        """

        XCTAssertEqual(PowerManager.parseSleepDisabledValue(from: output), true)
    }

    func testReturnsNilWhenSleepDisabledIsMissing() {
        XCTAssertNil(PowerManager.parseSleepDisabledValue(from: "sleep 1"))
    }
}
