import XCTest
@testable import AgentKeepPrivilegedCore

final class KeepAwakeCommandTests: XCTestCase {
    func testEnableCommandUsesFixedPmsetInvocation() {
        let command = KeepAwakeCommand.setKeepAwake(enabled: true)

        XCTAssertEqual(command.executableURL.path, "/usr/bin/pmset")
        XCTAssertEqual(command.arguments, ["-a", "disablesleep", "1"])
    }

    func testDisableCommandUsesFixedPmsetInvocation() {
        let command = KeepAwakeCommand.setKeepAwake(enabled: false)

        XCTAssertEqual(command.executableURL.path, "/usr/bin/pmset")
        XCTAssertEqual(command.arguments, ["-a", "disablesleep", "0"])
    }
}
