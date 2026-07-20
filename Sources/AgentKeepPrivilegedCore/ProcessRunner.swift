import Foundation

struct KeepAwakeProcessResult: Equatable {
    let terminationStatus: Int32
    let standardOutput: String
    let standardError: String
}

protocol KeepAwakeProcessRunning {
    func run(_ command: KeepAwakeCommand) throws -> KeepAwakeProcessResult
}

struct FoundationKeepAwakeProcessRunner: KeepAwakeProcessRunning {
    private let maximumCapturedBytes = 4_096

    func run(_ command: KeepAwakeCommand) throws -> KeepAwakeProcessResult {
        let process = Process()
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        let outputReader = BoundedPipeReader(maximumBytes: maximumCapturedBytes)
        let errorReader = BoundedPipeReader(maximumBytes: maximumCapturedBytes)
        let readGroup = DispatchGroup()

        process.executableURL = command.executableURL
        process.arguments = command.arguments
        process.environment = [:]
        process.currentDirectoryURL = URL(fileURLWithPath: "/", isDirectory: true)
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        outputReader.startReading(outputPipe.fileHandleForReading, group: readGroup)
        errorReader.startReading(errorPipe.fileHandleForReading, group: readGroup)

        do {
            try process.run()
        } catch {
            outputPipe.fileHandleForWriting.closeFile()
            errorPipe.fileHandleForWriting.closeFile()
            readGroup.wait()
            throw error
        }

        outputPipe.fileHandleForWriting.closeFile()
        errorPipe.fileHandleForWriting.closeFile()
        process.waitUntilExit()
        readGroup.wait()

        return KeepAwakeProcessResult(
            terminationStatus: process.terminationStatus,
            standardOutput: outputReader.string,
            standardError: errorReader.string
        )
    }
}

private final class BoundedPipeReader {
    private let maximumBytes: Int
    private var capturedData = Data()

    init(maximumBytes: Int) {
        self.maximumBytes = maximumBytes
    }

    var string: String {
        String(decoding: capturedData, as: UTF8.self)
    }

    func startReading(_ fileHandle: FileHandle, group: DispatchGroup) {
        group.enter()
        DispatchQueue.global(qos: .utility).async { [self] in
            defer {
                fileHandle.closeFile()
                group.leave()
            }

            while true {
                let chunk: Data

                do {
                    chunk = try fileHandle.read(upToCount: 4_096) ?? Data()
                } catch {
                    return
                }

                guard !chunk.isEmpty else {
                    return
                }

                let remainingCapacity = maximumBytes - capturedData.count

                if remainingCapacity > 0 {
                    capturedData.append(chunk.prefix(remainingCapacity))
                }
            }
        }
    }
}
