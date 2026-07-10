import Darwin
import Foundation

struct LocalServerListener: Hashable {
    let address: String
    let port: Int
    let rawName: String
}

struct LocalServerProcess: Hashable {
    let pid: Int32
    let processName: String
    let commandLine: String?
    let workingDirectory: String?
    let listeners: [LocalServerListener]
    let kind: LocalServerKind

    var sortedPorts: [Int] {
        Array(Set(listeners.map(\.port))).sorted()
    }

    var projectName: String? {
        guard let workingDirectory else {
            return nil
        }

        return URL(fileURLWithPath: workingDirectory).lastPathComponent
    }
}

enum LocalServerKind: String {
    case node = "Node.js"
    case php = "PHP"
    case python = "Python"
    case ruby = "Ruby"
    case bun = "Bun"
    case deno = "Deno"
    case dotnet = ".NET"
    case java = "Java"
    case go = "Go"
    case rust = "Rust"
    case other = "Local"
}

struct LocalServerStopFailure: Hashable {
    let process: LocalServerProcess
    let message: String
}

struct LocalServerStopResult {
    let stopped: [LocalServerProcess]
    let failures: [LocalServerStopFailure]
}

struct LocalServerMonitor {
    private let lsofPath = "/usr/sbin/lsof"
    private let psPath = "/bin/ps"

    func currentServers() throws -> [LocalServerProcess] {
        let lsofOutput = try runProcess(
            executablePath: lsofPath,
            arguments: ["-nP", "-iTCP", "-sTCP:LISTEN", "-F", "pcn"],
            allowedStatusCodes: [0, 1]
        )

        let records = Self.parseLsofOutput(lsofOutput)
        let pids = records.map(\.pid)
        let cwdByPID = try currentWorkingDirectories(for: pids)
        let commandByPID = try commandLines(for: pids)

        return records.compactMap { record in
            let commandLine = commandByPID[record.pid]
            let workingDirectory = cwdByPID[record.pid]

            guard let kind = Self.kind(
                processName: record.processName,
                commandLine: commandLine,
                workingDirectory: workingDirectory
            ) else {
                return nil
            }

            let process = LocalServerProcess(
                pid: record.pid,
                processName: record.processName,
                commandLine: commandLine,
                workingDirectory: workingDirectory,
                listeners: record.listeners,
                kind: kind
            )

            guard Self.isLikelyLocalDevelopmentServer(process) else {
                return nil
            }

            return process
        }
        .sorted { lhs, rhs in
            let lhsPort = lhs.sortedPorts.first ?? Int.max
            let rhsPort = rhs.sortedPorts.first ?? Int.max

            if lhsPort != rhsPort {
                return lhsPort < rhsPort
            }

            return lhs.pid < rhs.pid
        }
    }

    func stop(_ processes: [LocalServerProcess]) -> LocalServerStopResult {
        let uniqueProcesses = Array(Dictionary(grouping: processes, by: \.pid).compactMap { $0.value.first })
            .filter { $0.pid != getpid() }

        var failures: [LocalServerStopFailure] = []
        var stopped: [LocalServerProcess] = []

        for process in uniqueProcesses {
            if let message = sendSignal(SIGTERM, to: process.pid) {
                failures.append(LocalServerStopFailure(process: process, message: message))
            } else {
                stopped.append(process)
            }
        }

        Thread.sleep(forTimeInterval: 1.0)

        let failedPIDs = Set(failures.map { $0.process.pid })

        for process in uniqueProcesses where !failedPIDs.contains(process.pid) && isProcessRunning(process.pid) {
            if let message = sendSignal(SIGKILL, to: process.pid) {
                failures.append(LocalServerStopFailure(process: process, message: message))
            }
        }

        return LocalServerStopResult(stopped: stopped, failures: failures)
    }

    static func parseLsofOutput(_ output: String) -> [ParsedLsofRecord] {
        var records: [Int32: ParsedLsofRecord] = [:]
        var currentPID: Int32?

        for rawLine in output.components(separatedBy: .newlines) {
            guard let field = rawLine.first else {
                continue
            }

            let value = String(rawLine.dropFirst())

            switch field {
            case "p":
                guard let pid = Int32(value) else {
                    currentPID = nil
                    continue
                }

                currentPID = pid

                if records[pid] == nil {
                    records[pid] = ParsedLsofRecord(pid: pid, processName: "", listeners: [])
                }
            case "c":
                guard let currentPID, var record = records[currentPID] else {
                    continue
                }

                record.processName = value
                records[currentPID] = record
            case "n":
                guard let currentPID, var record = records[currentPID],
                      let listener = parseListenerName(value) else {
                    continue
                }

                if !record.listeners.contains(listener) {
                    record.listeners.append(listener)
                }

                records[currentPID] = record
            default:
                continue
            }
        }

        return records.values
            .filter { !$0.listeners.isEmpty }
            .map { record in
                ParsedLsofRecord(
                    pid: record.pid,
                    processName: record.processName,
                    listeners: record.listeners.sorted { lhs, rhs in
                        if lhs.port != rhs.port {
                            return lhs.port < rhs.port
                        }

                        return lhs.address < rhs.address
                    }
                )
            }
            .sorted { $0.pid < $1.pid }
    }

    static func parseCwdOutput(_ output: String) -> [Int32: String] {
        var result: [Int32: String] = [:]
        var currentPID: Int32?

        for rawLine in output.components(separatedBy: .newlines) {
            guard let field = rawLine.first else {
                continue
            }

            let value = String(rawLine.dropFirst())

            switch field {
            case "p":
                currentPID = Int32(value)
            case "n":
                guard let currentPID else {
                    continue
                }

                result[currentPID] = value
            default:
                continue
            }
        }

        return result
    }

    static func parsePsOutput(_ output: String) -> [Int32: String] {
        var result: [Int32: String] = [:]

        for rawLine in output.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)

            guard !line.isEmpty,
                  let separator = line.firstIndex(where: { $0 == " " || $0 == "\t" }) else {
                continue
            }

            let pidValue = String(line[..<separator])
            let command = String(line[separator...]).trimmingCharacters(in: .whitespacesAndNewlines)

            guard let pid = Int32(pidValue), !command.isEmpty else {
                continue
            }

            result[pid] = command
        }

        return result
    }

    private func currentWorkingDirectories(for pids: [Int32]) throws -> [Int32: String] {
        guard !pids.isEmpty else {
            return [:]
        }

        let output = try runProcess(
            executablePath: lsofPath,
            arguments: ["-a", "-p", pids.map(String.init).joined(separator: ","), "-d", "cwd", "-Fn"],
            allowedStatusCodes: [0, 1]
        )

        return Self.parseCwdOutput(output)
    }

    private func commandLines(for pids: [Int32]) throws -> [Int32: String] {
        guard !pids.isEmpty else {
            return [:]
        }

        let output = try runProcess(
            executablePath: psPath,
            arguments: ["-p", pids.map(String.init).joined(separator: ","), "-o", "pid=", "-o", "command="],
            allowedStatusCodes: [0, 1]
        )

        return Self.parsePsOutput(output)
    }

    private static func parseListenerName(_ name: String) -> LocalServerListener? {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)

        guard let port = parsePort(from: trimmedName) else {
            return nil
        }

        return LocalServerListener(
            address: parseAddress(from: trimmedName),
            port: port,
            rawName: trimmedName
        )
    }

    private static func parsePort(from name: String) -> Int? {
        guard let colonIndex = name.lastIndex(of: ":") else {
            return nil
        }

        let suffix = name[name.index(after: colonIndex)...]
        let digits = suffix.prefix { $0.isNumber }

        guard !digits.isEmpty else {
            return nil
        }

        return Int(digits)
    }

    private static func parseAddress(from name: String) -> String {
        guard let colonIndex = name.lastIndex(of: ":") else {
            return name
        }

        let address = String(name[..<colonIndex])
            .replacingOccurrences(of: "TCP ", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        return address.isEmpty ? "*" : address
    }

    private static func kind(
        processName: String,
        commandLine: String?,
        workingDirectory: String?
    ) -> LocalServerKind? {
        let searchable = normalizedSearchText(
            [processName, commandLine ?? "", workingDirectory ?? ""].joined(separator: " ")
        )
        let processToken = processName.lowercased()

        if containsAny(["node", "npm", "npx", "pnpm", "yarn", "vite", "next", "astro", "webpack"], in: searchable) {
            return .node
        }

        if containsAny(["bun"], in: searchable) {
            return .bun
        }

        if containsAny(["deno"], in: searchable) {
            return .deno
        }

        if containsAny(["php", "artisan", "symfony"], in: searchable) {
            return .php
        }

        if containsAny(["python", "python3", "uvicorn", "gunicorn", "flask", "django"], in: searchable) {
            return .python
        }

        if containsAny(["ruby", "rails", "puma", "rackup"], in: searchable) {
            return .ruby
        }

        if containsAny(["dotnet", "kestrel"], in: searchable) {
            return .dotnet
        }

        if processToken == "java", isProjectDirectory(workingDirectory) {
            return .java
        }

        if containsAny(["go", "air"], in: searchable), isProjectDirectory(workingDirectory) {
            return .go
        }

        if containsAny(["cargo"], in: searchable), isProjectDirectory(workingDirectory) {
            return .rust
        }

        if isProjectDirectory(workingDirectory) {
            return .other
        }

        return nil
    }

    private static func isLikelyLocalDevelopmentServer(_ process: LocalServerProcess) -> Bool {
        guard process.listeners.contains(where: isLocalDevelopmentListener) else {
            return false
        }

        if process.kind == .other {
            return isProjectDirectory(process.workingDirectory)
        }

        return process.sortedPorts.contains(where: { $0 >= 1024 })
    }

    private static func isLocalDevelopmentListener(_ listener: LocalServerListener) -> Bool {
        guard listener.port >= 1024 else {
            return false
        }

        let address = listener.address
            .replacingOccurrences(of: "[", with: "")
            .replacingOccurrences(of: "]", with: "")
            .lowercased()

        return address == "*"
            || address == "localhost"
            || address == "0.0.0.0"
            || address == "::"
            || address == "::1"
            || address.hasPrefix("127.")
    }

    private static func isProjectDirectory(_ workingDirectory: String?) -> Bool {
        guard let workingDirectory else {
            return false
        }

        let homeDirectory = NSHomeDirectory()

        guard workingDirectory.hasPrefix(homeDirectory + "/") else {
            return false
        }

        let excludedPrefixes = [
            homeDirectory + "/Library/",
            homeDirectory + "/Applications/"
        ]

        return !excludedPrefixes.contains { workingDirectory.hasPrefix($0) }
    }

    private static func normalizedSearchText(_ value: String) -> Set<String> {
        let separators = CharacterSet.alphanumerics.inverted

        return Set(
            value
                .lowercased()
                .components(separatedBy: separators)
                .filter { !$0.isEmpty }
        )
    }

    private static func containsAny(_ values: [String], in searchText: Set<String>) -> Bool {
        values.contains { searchText.contains($0) }
    }

    private func sendSignal(_ signal: Int32, to pid: Int32) -> String? {
        if Darwin.kill(pid, signal) == 0 {
            return nil
        }

        if errno == ESRCH {
            return nil
        }

        return String(cString: strerror(errno))
    }

    private func isProcessRunning(_ pid: Int32) -> Bool {
        if Darwin.kill(pid, 0) == 0 {
            return true
        }

        return errno != ESRCH
    }

    private func runProcess(
        executablePath: String,
        arguments: [String],
        allowedStatusCodes: Set<Int32>
    ) throws -> String {
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

        guard allowedStatusCodes.contains(process.terminationStatus) else {
            throw LocalServerMonitorError.commandFailed(
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

struct ParsedLsofRecord: Hashable {
    let pid: Int32
    var processName: String
    var listeners: [LocalServerListener]
}

enum LocalServerMonitorError: Error, LocalizedError {
    case commandFailed(
        executablePath: String,
        arguments: [String],
        status: Int32,
        output: String,
        error: String
    )

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
        }
    }
}
