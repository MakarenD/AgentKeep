import XCTest
@testable import AgentKeepCore

final class StatusItemPresentationTests: XCTestCase {
    func testPresentsZeroTrackedProcesses() {
        let presentation = StatusItemPresentation(localServerCount: 0)

        XCTAssertEqual(presentation.title, "0")
        XCTAssertEqual(presentation.fallbackTitle, "AK 0")
        XCTAssertEqual(presentation.processSummary, "0 local servers running")
    }

    func testPresentsOneTrackedProcess() {
        let presentation = StatusItemPresentation(localServerCount: 1)

        XCTAssertEqual(presentation.title, "1")
        XCTAssertEqual(presentation.fallbackTitle, "AK 1")
        XCTAssertEqual(presentation.processSummary, "1 local server running")
    }

    func testPresentsMultipleTrackedProcesses() {
        let presentation = StatusItemPresentation(localServerCount: 12)

        XCTAssertEqual(presentation.title, "12")
        XCTAssertEqual(presentation.fallbackTitle, "AK 12")
        XCTAssertEqual(presentation.processSummary, "12 local servers running")
    }

    func testPresentsUnavailableCountAfterScanFailure() {
        let presentation = StatusItemPresentation(localServerCount: nil)

        XCTAssertEqual(presentation.title, "–")
        XCTAssertEqual(presentation.fallbackTitle, "AK –")
        XCTAssertEqual(presentation.processSummary, "Local server count unavailable")
    }
}
