import AgentKeepIPC
import Foundation
import ServiceManagement

final class PrivilegedHelperClient {
    private let service: SMAppService
    private let replyTimeout: TimeInterval

    init(
        service: SMAppService = .daemon(plistName: AgentKeepPrivilegedConstants.daemonPlistName),
        replyTimeout: TimeInterval = 15
    ) {
        self.service = service
        self.replyTimeout = replyTimeout
    }

    func setKeepAwake(enabled: Bool) throws {
        do {
            try sendSetKeepAwakeRequest(enabled: enabled)
        } catch PrivilegedHelperClientError.helperVersionMismatch {
            try reregisterService()
            try sendSetKeepAwakeRequest(enabled: enabled)
        }
    }

    func openApprovalSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }

    private func sendSetKeepAwakeRequest(enabled: Bool) throws {
        let requirement: String

        do {
            requirement = try CodeSigningRequirement.sameTeam(
                signingIdentifier: AgentKeepPrivilegedConstants.helperSigningIdentifier
            )
        } catch {
            throw PrivilegedHelperClientError.signingValidationFailed(error.localizedDescription)
        }

        try ensureServiceIsEnabled()

        let connection = NSXPCConnection(
            machServiceName: AgentKeepPrivilegedConstants.machServiceName,
            options: .privileged
        )
        let reply = PrivilegedHelperReply()

        connection.remoteObjectInterface = NSXPCInterface(
            with: AgentKeepPrivilegedHelperProtocol.self
        )
        connection.setCodeSigningRequirement(requirement)
        connection.interruptionHandler = {
            reply.complete(
                .failure(PrivilegedHelperClientError.connectionFailed("The helper connection was interrupted."))
            )
        }
        connection.invalidationHandler = {
            reply.complete(
                .failure(PrivilegedHelperClientError.connectionFailed("The helper connection was invalidated."))
            )
        }
        connection.resume()

        defer {
            connection.invalidate()
        }

        guard let proxy = connection.remoteObjectProxyWithErrorHandler({ error in
            reply.complete(
                .failure(PrivilegedHelperClientError.connectionFailed(error.localizedDescription))
            )
        }) as? AgentKeepPrivilegedHelperProtocol else {
            throw PrivilegedHelperClientError.connectionFailed("The helper XPC proxy is unavailable.")
        }

        proxy.helperVersion { helperVersion in
            guard helperVersion == AgentKeepPrivilegedConstants.helperVersion else {
                reply.complete(.failure(PrivilegedHelperClientError.helperVersionMismatch))
                return
            }

            proxy.setKeepAwake(enabled) { error in
                if let error {
                    reply.complete(.failure(error))
                } else {
                    reply.complete(.success(()))
                }
            }
        }

        guard let result = reply.wait(timeout: replyTimeout) else {
            throw PrivilegedHelperClientError.timedOut
        }

        try result.get()
    }

    private func ensureServiceIsEnabled() throws {
        let initialStatus = service.status

        if Self.shouldAttemptRegistration(for: initialStatus) {
            do {
                try service.register()
            } catch {
                if service.status == .requiresApproval
                    || Self.isApprovalRequiredRegistrationError(error) {
                    throw PrivilegedHelperClientError.approvalRequired
                }

                throw PrivilegedHelperClientError.registrationFailed(error.localizedDescription)
            }

            switch service.status {
            case .enabled:
                return
            case .requiresApproval, .notRegistered:
                throw PrivilegedHelperClientError.approvalRequired
            case .notFound:
                throw PrivilegedHelperClientError.helperNotFound
            @unknown default:
                throw PrivilegedHelperClientError.unknownServiceStatus
            }
        }

        switch initialStatus {
        case .enabled:
            return
        case .requiresApproval:
            throw PrivilegedHelperClientError.approvalRequired
        case .notRegistered, .notFound:
            throw PrivilegedHelperClientError.unknownServiceStatus
        @unknown default:
            throw PrivilegedHelperClientError.unknownServiceStatus
        }
    }

    private func reregisterService() throws {
        let reply = PrivilegedHelperReply()

        service.unregister { error in
            if let error {
                reply.complete(
                    .failure(PrivilegedHelperClientError.registrationFailed(error.localizedDescription))
                )
            } else {
                reply.complete(.success(()))
            }
        }

        guard let result = reply.wait(timeout: replyTimeout) else {
            throw PrivilegedHelperClientError.timedOut
        }

        try result.get()
        try ensureServiceIsEnabled()
    }

    static func isApprovalRequiredRegistrationError(_ error: Error) -> Bool {
        let error = error as NSError

        if error.domain == "SMAppServiceErrorDomain", error.code == 1 {
            return true
        }

        return error.domain == NSOSStatusErrorDomain
            && error.code == Int(kSMErrorLaunchDeniedByUser)
    }

    static func shouldAttemptRegistration(for status: SMAppService.Status) -> Bool {
        status == .notRegistered || status == .notFound
    }
}

enum PrivilegedHelperClientError: Error, LocalizedError {
    case approvalRequired
    case helperNotFound
    case registrationFailed(String)
    case signingValidationFailed(String)
    case connectionFailed(String)
    case timedOut
    case helperVersionMismatch
    case unknownServiceStatus

    var requiresApproval: Bool {
        if case .approvalRequired = self {
            return true
        }

        return false
    }

    var errorDescription: String? {
        switch self {
        case .approvalRequired:
            return "Allow the AgentKeep background item in System Settings > General > Login Items, then enable Keep-Awake again. macOS normally requests this administrator approval once, but may request it again after updates or permission changes."
        case .helperNotFound:
            return "The privileged helper is missing from the AgentKeep app bundle. Reinstall AgentKeep from its signed package."
        case .registrationFailed(let message):
            return "The privileged helper could not be registered: \(message)"
        case .signingValidationFailed(let message):
            return "The privileged helper requires an AgentKeep build signed with an Apple Development or Developer ID certificate: \(message)"
        case .connectionFailed(let message):
            return "The privileged helper could not complete the request: \(message)"
        case .timedOut:
            return "The privileged helper did not respond within 15 seconds."
        case .helperVersionMismatch:
            return "The installed privileged helper is out of date."
        case .unknownServiceStatus:
            return "macOS returned an unknown privileged helper status."
        }
    }
}

private final class PrivilegedHelperReply {
    private let condition = NSCondition()
    private var result: Result<Void, Error>?

    func complete(_ newResult: Result<Void, Error>) {
        condition.lock()

        if result == nil {
            result = newResult
            condition.signal()
        }

        condition.unlock()
    }

    func wait(timeout: TimeInterval) -> Result<Void, Error>? {
        let deadline = Date(timeIntervalSinceNow: timeout)
        condition.lock()
        defer { condition.unlock() }

        while result == nil {
            guard condition.wait(until: deadline) else {
                return nil
            }
        }

        return result
    }
}
