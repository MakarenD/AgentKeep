import XCTest
@testable import AgentKeepCore

final class QuitCleanupGateTests: XCTestCase {
    func testWaitsForInFlightKeepAwakeOperation() {
        XCTAssertFalse(QuitCleanupGate.shouldStart(
            isPreparingToQuit: true,
            isWorking: true,
            isCleanupRunning: false
        ))
    }

    func testStartsAfterInFlightOperationFinishes() {
        XCTAssertTrue(QuitCleanupGate.shouldStart(
            isPreparingToQuit: true,
            isWorking: false,
            isCleanupRunning: false
        ))
    }

    func testDoesNotStartTwice() {
        XCTAssertFalse(QuitCleanupGate.shouldStart(
            isPreparingToQuit: true,
            isWorking: false,
            isCleanupRunning: true
        ))
    }

    func testDoesNotStartOutsideTermination() {
        XCTAssertFalse(QuitCleanupGate.shouldStart(
            isPreparingToQuit: false,
            isWorking: false,
            isCleanupRunning: false
        ))
    }

    func testDoesNotRegisterHelperWhenKeepAwakeIsAlreadyDisabled() {
        XCTAssertFalse(QuitCleanupGate.shouldDisableKeepAwake(currentState: false))
    }

    func testDisablesKeepAwakeBeforeTerminationWhenItIsEnabled() {
        XCTAssertTrue(QuitCleanupGate.shouldDisableKeepAwake(currentState: true))
    }
}
