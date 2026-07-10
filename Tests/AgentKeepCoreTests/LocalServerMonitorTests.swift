import XCTest
@testable import AgentKeepCore

final class LocalServerMonitorTests: XCTestCase {
    func testParsesLsofOutputWithMultipleListenersForOneProcess() {
        let output = """
        p1234
        cnode
        n*:3000
        n127.0.0.1:5173
        p2345
        cphp
        nlocalhost:8000
        """

        let records = LocalServerMonitor.parseLsofOutput(output)

        XCTAssertEqual(records.count, 2)
        XCTAssertEqual(records[0].pid, 1234)
        XCTAssertEqual(records[0].processName, "node")
        XCTAssertEqual(records[0].listeners.map(\.port), [3000, 5173])
        XCTAssertEqual(records[1].pid, 2345)
        XCTAssertEqual(records[1].processName, "php")
        XCTAssertEqual(records[1].listeners.map(\.port), [8000])
    }

    func testParsesIPv6ListenerPort() {
        let output = """
        p1234
        cnode
        n[::1]:3000
        """

        let records = LocalServerMonitor.parseLsofOutput(output)

        XCTAssertEqual(records.first?.listeners.first?.address, "[::1]")
        XCTAssertEqual(records.first?.listeners.first?.port, 3000)
    }

    func testParsesCwdOutput() {
        let output = """
        p1234
        n/Users/kirill/project-one
        p2345
        n/Users/kirill/project-two
        """

        XCTAssertEqual(
            LocalServerMonitor.parseCwdOutput(output),
            [
                1234: "/Users/kirill/project-one",
                2345: "/Users/kirill/project-two"
            ]
        )
    }

    func testParsesPsOutput() {
        let output = """
          1234 /opt/homebrew/bin/node ./server.js --port 3000
          2345 php -S localhost:8000
        """

        XCTAssertEqual(
            LocalServerMonitor.parsePsOutput(output),
            [
                1234: "/opt/homebrew/bin/node ./server.js --port 3000",
                2345: "php -S localhost:8000"
            ]
        )
    }
}
