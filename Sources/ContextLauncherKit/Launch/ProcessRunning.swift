import Foundation

public protocol ProcessRunning: AnyObject {
    func run(executable: URL, arguments: [String]) throws
}

public final class ProcessRunner: ProcessRunning {
    public init() {}

    public func run(executable: URL, arguments: [String]) throws {
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        try process.run()
    }
}
