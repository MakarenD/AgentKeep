import Foundation

struct PowerManager {
    private let pmsetPath = "/usr/bin/pmset"
    private let osascriptPath = "/usr/bin/osascript"

    func currentKeepAwakeState() throws -> Bool {
        let output = try runProcess(executablePath: pmsetPath, arguments: ["-g"])

        if let value = Self.parseSleepDisabledValue(from: output) {
            return value
        }

        throw PowerManagerError.unreadablePmsetOutput(output)
    }

    func setKeepAwake(enabled: Bool) throws {
        let value = enabled ? "1" : "0"
        let command = "\(pmsetPath) -a disablesleep \(value)"
        let script = "do shell script \(Self.appleScriptString(command)) with administrator privileges"

        _ = try runProcess(executablePath: osascriptPath, arguments: ["-e", script])
    }

    static func parseSleepDisabledValue(from output: String) -> Bool? {
        for line in output.components(separatedBy: .newlines) {
            let fields = line.split(whereSeparator: { $0 == " " || $0 == "\t" })

            guard fields.count >= 2 else {
                continue
            }

            let key = fields[0].lowercased()

            guard key == "sleepdisabled" || key == "disablesleep" else {
                continue
            }

            if fields[1] == "1" {
                return true
            }

            if fields[1] == "0" {
                return false
            }
        }

        return nil
    }

    private static func appleScriptString(_ value: String) -> String {
        let escaped = value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")

        return "\"\(escaped)\""
    }

    private func runProcess(executablePath: String, arguments: [String]) throws -> String {
        let process = Process()
        let outputPipe = Pipe()
        let errorPipe = Pipe()

        process.executableURL = URL(fileURLWithPath: executablePath)
        process.arguments = arguments
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        try process.run()
        process.waitUntilExit()

        let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
        let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: outputData, encoding: .utf8) ?? ""
        let error = String(data: errorData, encoding: .utf8) ?? ""

        guard process.terminationStatus == 0 else {
            throw PowerManagerError.commandFailed(
                executablePath: executablePath,
                arguments: arguments,
                status: process.terminationStatus,
                output: output,
                error: error
            )
        }

        return output
    }
}

enum PowerManagerError: Error, LocalizedError {
    case commandFailed(
        executablePath: String,
        arguments: [String],
        status: Int32,
        output: String,
        error: String
    )
    case unreadablePmsetOutput(String)

    var errorDescription: String? {
        switch self {
        case .commandFailed(let executablePath, let arguments, let status, let output, let error):
            let details = [error, output]
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
                .joined(separator: "\n")

            let command = ([executablePath] + arguments).joined(separator: " ")

            if details.isEmpty {
                return "\(command) failed with exit code \(status)."
            }

            return "\(command) failed with exit code \(status):\n\(details)"
        case .unreadablePmsetOutput(let output):
            return "Could not find SleepDisabled in pmset output:\n\(output)"
        }
    }
}
