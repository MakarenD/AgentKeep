import Foundation
import ServiceManagement
import XCTest
@testable import AgentKeepCore

final class PrivilegedHelperClientTests: XCTestCase {
    func testAttemptsRegistrationWhenServiceIsNotRegistered() {
        XCTAssertTrue(PrivilegedHelperClient.shouldAttemptRegistration(for: .notRegistered))
    }

    func testAttemptsRegistrationWhenInitialStatusIsNotFound() {
        XCTAssertTrue(PrivilegedHelperClient.shouldAttemptRegistration(for: .notFound))
    }

    func testDoesNotRegisterServiceThatIsEnabledOrAwaitingApproval() {
        XCTAssertFalse(PrivilegedHelperClient.shouldAttemptRegistration(for: .enabled))
        XCTAssertFalse(PrivilegedHelperClient.shouldAttemptRegistration(for: .requiresApproval))
    }

    func testRecognizesModernApprovalError() {
        let error = NSError(domain: "SMAppServiceErrorDomain", code: 1)

        XCTAssertTrue(PrivilegedHelperClient.isApprovalRequiredRegistrationError(error))
    }

    func testRecognizesLegacyLaunchDeniedError() {
        let error = NSError(
            domain: NSOSStatusErrorDomain,
            code: Int(kSMErrorLaunchDeniedByUser)
        )

        XCTAssertTrue(PrivilegedHelperClient.isApprovalRequiredRegistrationError(error))
    }

    func testRejectsUnrelatedRegistrationError() {
        let error = NSError(domain: NSCocoaErrorDomain, code: NSFileNoSuchFileError)

        XCTAssertFalse(PrivilegedHelperClient.isApprovalRequiredRegistrationError(error))
    }

    func testRejectsMatchingLegacyCodeFromUnrelatedDomain() {
        let error = NSError(
            domain: NSCocoaErrorDomain,
            code: Int(kSMErrorLaunchDeniedByUser)
        )

        XCTAssertFalse(PrivilegedHelperClient.isApprovalRequiredRegistrationError(error))
    }
}
