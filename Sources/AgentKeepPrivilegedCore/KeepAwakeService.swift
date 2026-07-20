import AgentKeepIPC
import Foundation

public enum KeepAwakeServiceErrorCode: Int {
    case processLaunchFailed = 1
    case commandFailed = 2
}

public final class KeepAwakeService: NSObject, AgentKeepPrivilegedHelperProtocol {
    public static let errorDomain = "com.agentkeep.AgentKeep.PrivilegedHelper"

    private static let maximumErrorDetailCharacters = 4_096

    private let runner: any KeepAwakeProcessRunning
    private let workQueue = DispatchQueue(
        label: "com.agentkeep.AgentKeep.PrivilegedHelper.keep-awake"
    )

    public override convenience init() {
        self.init(runner: FoundationKeepAwakeProcessRunner())
    }

    init(runner: any KeepAwakeProcessRunning) {
        self.runner = runner
        super.init()
    }

    public func helperVersion(withReply reply: @escaping (Int) -> Void) {
        reply(AgentKeepPrivilegedConstants.helperVersion)
    }

    public func setKeepAwake(
        _ enabled: Bool,
        withReply reply: @escaping (NSError?) -> Void
    ) {
        workQueue.async { [runner] in
            let command = KeepAwakeCommand.setKeepAwake(enabled: enabled)

            do {
                let result = try runner.run(command)

                guard result.terminationStatus == 0 else {
                    reply(Self.commandFailedError(result))
                    return
                }

                reply(nil)
            } catch {
                reply(Self.processLaunchFailedError(error))
            }
        }
    }

    private static func processLaunchFailedError(_ error: Error) -> NSError {
        NSError(
            domain: errorDomain,
            code: KeepAwakeServiceErrorCode.processLaunchFailed.rawValue,
            userInfo: [
                NSLocalizedDescriptionKey: "AgentKeep could not start pmset.",
                NSLocalizedFailureReasonErrorKey: bounded(error.localizedDescription)
            ]
        )
    }

    private static func commandFailedError(_ result: KeepAwakeProcessResult) -> NSError {
        let details = [result.standardError, result.standardOutput]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")

        var userInfo: [String: Any] = [
            NSLocalizedDescriptionKey: "pmset failed with exit code \(result.terminationStatus)."
        ]

        if !details.isEmpty {
            userInfo[NSLocalizedFailureReasonErrorKey] = bounded(details)
        }

        return NSError(
            domain: errorDomain,
            code: KeepAwakeServiceErrorCode.commandFailed.rawValue,
            userInfo: userInfo
        )
    }

    private static func bounded(_ value: String) -> String {
        if value.count <= maximumErrorDetailCharacters {
            return value
        }

        return String(value.prefix(maximumErrorDetailCharacters))
    }
}
