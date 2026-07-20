import Foundation

public struct KeepAwakeCommand: Equatable, Sendable {
    public static let pmsetExecutableURL = URL(fileURLWithPath: "/usr/bin/pmset")

    public let executableURL: URL
    public let arguments: [String]

    public static func setKeepAwake(enabled: Bool) -> KeepAwakeCommand {
        KeepAwakeCommand(
            executableURL: pmsetExecutableURL,
            arguments: ["-a", "disablesleep", enabled ? "1" : "0"]
        )
    }

    private init(executableURL: URL, arguments: [String]) {
        self.executableURL = executableURL
        self.arguments = arguments
    }
}
