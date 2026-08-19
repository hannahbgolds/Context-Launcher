import Foundation

public protocol ProcessRunning: AnyObject {
    func run(executable: URL, arguments: [String]) throws
}

public enum ProcessRunnerError: LocalizedError, Equatable {
    case nonzeroExit(executable: URL, status: Int32)

    public var errorDescription: String? {
        switch self {
        case let .nonzeroExit(executable, status):
            return "\(executable.path) exited with status \(status)."
        }
    }
}

public final class ProcessRunner: ProcessRunning {
    public init() {}

    public func run(executable: URL, arguments: [String]) throws {
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw ProcessRunnerError.nonzeroExit(executable: executable, status: process.terminationStatus)
        }
    }
}
