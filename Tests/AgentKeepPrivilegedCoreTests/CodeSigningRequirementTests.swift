import Security
import XCTest
@testable import AgentKeepIPC

final class CodeSigningRequirementTests: XCTestCase {
    func testBuildsParseableSameTeamRequirement() throws {
        let requirement = try CodeSigningRequirement.sameTeam(
            signingIdentifier: "com.agentkeep.AgentKeep",
            teamIdentifier: "ABCDE12345"
        )

        XCTAssertEqual(
            requirement,
            "anchor apple generic and identifier \"com.agentkeep.AgentKeep\" and certificate leaf[subject.OU] = \"ABCDE12345\""
        )

        var parsedRequirement: SecRequirement?
        let status = SecRequirementCreateWithString(
            requirement as CFString,
            SecCSFlags(),
            &parsedRequirement
        )

        XCTAssertEqual(status, errSecSuccess)
        XCTAssertNotNil(parsedRequirement)
    }

    func testRejectsMissingTeamIdentifier() {
        XCTAssertThrowsError(
            try CodeSigningRequirement.sameTeam(
                signingIdentifier: "com.agentkeep.AgentKeep",
                teamIdentifier: nil
            )
        ) { error in
            XCTAssertEqual(error as? CodeSigningRequirementError, .missingTeamIdentifier)
        }
    }

    func testRejectsMalformedTeamIdentifiers() {
        for teamIdentifier in [
            "",
            "SHORT",
            "abcde12345",
            "ABCDE1234!",
            "ABCDE123456"
        ] {
            XCTAssertThrowsError(
                try CodeSigningRequirement.sameTeam(
                    signingIdentifier: "com.agentkeep.AgentKeep",
                    teamIdentifier: teamIdentifier
                )
            ) { error in
                XCTAssertEqual(
                    error as? CodeSigningRequirementError,
                    .malformedTeamIdentifier(teamIdentifier)
                )
            }
        }
    }

    func testRejectsSigningIdentifierInjection() {
        let signingIdentifier = "com.agentkeep.AgentKeep\" or true"

        XCTAssertThrowsError(
            try CodeSigningRequirement.sameTeam(
                signingIdentifier: signingIdentifier,
                teamIdentifier: "ABCDE12345"
            )
        ) { error in
            XCTAssertEqual(
                error as? CodeSigningRequirementError,
                .malformedSigningIdentifier(signingIdentifier)
            )
        }
    }

    func testPrivilegedConstantsRemainConsistent() {
        XCTAssertEqual(
            AgentKeepPrivilegedConstants.daemonPlistName,
            AgentKeepPrivilegedConstants.machServiceName + ".plist"
        )
        XCTAssertEqual(
            AgentKeepPrivilegedConstants.helperSigningIdentifier,
            AgentKeepPrivilegedConstants.machServiceName
        )
        XCTAssertEqual(
            AgentKeepPrivilegedConstants.helperExecutableName,
            "AgentKeepPrivilegedHelper"
        )
    }
}
