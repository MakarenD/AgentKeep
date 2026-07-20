import AgentKeepIPC
import AgentKeepPrivilegedCore
import Darwin
import Foundation

private final class HelperListenerDelegate: NSObject, NSXPCListenerDelegate {
    private let service = KeepAwakeService()

    func listener(
        _ listener: NSXPCListener,
        shouldAcceptNewConnection newConnection: NSXPCConnection
    ) -> Bool {
        newConnection.exportedInterface = NSXPCInterface(
            with: AgentKeepPrivilegedHelperProtocol.self
        )
        newConnection.exportedObject = service
        newConnection.resume()
        return true
    }
}

private func fail(_ message: String, status: Int32) -> Never {
    FileHandle.standardError.write(Data("AgentKeep privileged helper: \(message)\n".utf8))
    exit(status)
}

guard geteuid() == 0 else {
    fail("refusing to run without root privileges", status: EX_NOPERM)
}

let callerRequirement: String

do {
    callerRequirement = try CodeSigningRequirement.sameTeam(
        signingIdentifier: AgentKeepPrivilegedConstants.appSigningIdentifier
    )
} catch {
    fail("could not create the caller requirement: \(error.localizedDescription)", status: EX_CONFIG)
}

let listener = NSXPCListener(
    machServiceName: AgentKeepPrivilegedConstants.machServiceName
)
private let listenerDelegate = HelperListenerDelegate()

listener.setConnectionCodeSigningRequirement(callerRequirement)
listener.delegate = listenerDelegate
listener.resume()
RunLoop.current.run()
