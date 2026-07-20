import Foundation
import AgentKeepIPC
import XCTest
@testable import AgentKeepPrivilegedCore

final class KeepAwakeServiceTests: XCTestCase {
    func testReportsCurrentHelperVersion() {
        let service = KeepAwakeService(runner: StubProcessRunner { _ in
            KeepAwakeProcessResult(terminationStatus: 0, standardOutput: "", standardError: "")
        })
        let replyExpectation = expectation(description: "reply")

        service.helperVersion { version in
            XCTAssertEqual(version, AgentKeepPrivilegedConstants.helperVersion)
            replyExpectation.fulfill()
        }

        wait(for: [replyExpectation], timeout: 1)
    }

    func testSuccessfulCommandRepliesWithoutError() {
        let runner = StubProcessRunner { _ in
            KeepAwakeProcessResult(
                terminationStatus: 0,
                standardOutput: "",
                standardError: ""
            )
        }
        let service = KeepAwakeService(runner: runner)
        let replyExpectation = expectation(description: "reply")

        service.setKeepAwake(true) { error in
            XCTAssertNil(error)
            replyExpectation.fulfill()
        }

        wait(for: [replyExpectation], timeout: 1)
        XCTAssertEqual(
            runner.commands,
            [KeepAwakeCommand.setKeepAwake(enabled: true)]
        )
    }

    func testNonzeroExitPropagatesBoundedError() {
        let runner = StubProcessRunner { _ in
            KeepAwakeProcessResult(
                terminationStatus: 7,
                standardOutput: "output",
                standardError: String(repeating: "x", count: 10_000)
            )
        }
        let service = KeepAwakeService(runner: runner)
        let replyExpectation = expectation(description: "reply")

        service.setKeepAwake(false) { error in
            XCTAssertEqual(error?.domain, KeepAwakeService.errorDomain)
            XCTAssertEqual(
                error?.code,
                KeepAwakeServiceErrorCode.commandFailed.rawValue
            )
            XCTAssertEqual(
                error?.localizedDescription,
                "pmset failed with exit code 7."
            )

            let reason = error?.userInfo[NSLocalizedFailureReasonErrorKey] as? String
            XCTAssertEqual(reason?.count, 4_096)
            replyExpectation.fulfill()
        }

        wait(for: [replyExpectation], timeout: 1)
    }

    func testProcessLaunchFailurePropagatesBoundedError() {
        let underlyingError = NSError(
            domain: "test",
            code: 42,
            userInfo: [
                NSLocalizedDescriptionKey: String(repeating: "failure", count: 1_000)
            ]
        )
        let runner = StubProcessRunner { _ in
            throw underlyingError
        }
        let service = KeepAwakeService(runner: runner)
        let replyExpectation = expectation(description: "reply")

        service.setKeepAwake(true) { error in
            XCTAssertEqual(error?.domain, KeepAwakeService.errorDomain)
            XCTAssertEqual(
                error?.code,
                KeepAwakeServiceErrorCode.processLaunchFailed.rawValue
            )

            let reason = error?.userInfo[NSLocalizedFailureReasonErrorKey] as? String
            XCTAssertEqual(reason?.count, 4_096)
            replyExpectation.fulfill()
        }

        wait(for: [replyExpectation], timeout: 1)
    }

    func testCommandsAreSerialized() {
        let runner = BlockingProcessRunner()
        let service = KeepAwakeService(runner: runner)
        let firstReply = expectation(description: "first reply")
        let secondReply = expectation(description: "second reply")

        service.setKeepAwake(true) { error in
            XCTAssertNil(error)
            firstReply.fulfill()
        }

        XCTAssertEqual(runner.firstCommandStarted.wait(timeout: .now() + 1), .success)

        service.setKeepAwake(false) { error in
            XCTAssertNil(error)
            secondReply.fulfill()
        }

        XCTAssertEqual(
            runner.secondCommandStarted.wait(timeout: .now() + 0.05),
            .timedOut
        )

        runner.releaseFirstCommand.signal()
        wait(for: [firstReply, secondReply], timeout: 1)
        XCTAssertEqual(
            runner.commands,
            [
                KeepAwakeCommand.setKeepAwake(enabled: true),
                KeepAwakeCommand.setKeepAwake(enabled: false)
            ]
        )
    }
}

private final class StubProcessRunner: KeepAwakeProcessRunning {
    private let lock = NSLock()
    private let handler: (KeepAwakeCommand) throws -> KeepAwakeProcessResult
    private var recordedCommands: [KeepAwakeCommand] = []

    init(handler: @escaping (KeepAwakeCommand) throws -> KeepAwakeProcessResult) {
        self.handler = handler
    }

    var commands: [KeepAwakeCommand] {
        lock.lock()
        defer { lock.unlock() }
        return recordedCommands
    }

    func run(_ command: KeepAwakeCommand) throws -> KeepAwakeProcessResult {
        lock.lock()
        recordedCommands.append(command)
        lock.unlock()
        return try handler(command)
    }
}

private final class BlockingProcessRunner: KeepAwakeProcessRunning {
    let firstCommandStarted = DispatchSemaphore(value: 0)
    let secondCommandStarted = DispatchSemaphore(value: 0)
    let releaseFirstCommand = DispatchSemaphore(value: 0)

    private let lock = NSLock()
    private var recordedCommands: [KeepAwakeCommand] = []

    var commands: [KeepAwakeCommand] {
        lock.lock()
        defer { lock.unlock() }
        return recordedCommands
    }

    func run(_ command: KeepAwakeCommand) throws -> KeepAwakeProcessResult {
        lock.lock()
        recordedCommands.append(command)
        let commandIndex = recordedCommands.count - 1
        lock.unlock()

        if commandIndex == 0 {
            firstCommandStarted.signal()
            _ = releaseFirstCommand.wait(timeout: .now() + 1)
        } else if commandIndex == 1 {
            secondCommandStarted.signal()
        }

        return KeepAwakeProcessResult(
            terminationStatus: 0,
            standardOutput: "",
            standardError: ""
        )
    }
}
