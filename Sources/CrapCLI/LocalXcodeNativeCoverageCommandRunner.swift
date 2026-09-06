import Foundation

struct LocalXcodeNativeCoverageCommandRunner: XcodeNativeCoverageCommandRunning {
    func run(arguments: [String]) throws -> (output: Data, error: Data, status: Int32) {
        guard arguments.starts(with: ["xcresulttool", "get", "test-results", "summary"]),
              let option = arguments.firstIndex(of: "--path"),
              arguments.indices.contains(option + 1)
        else { return try execute(arguments: arguments) }
        return try XcodeResultBundleCopy().read(at: arguments[option + 1]) { path in
            var copiedArguments = arguments
            copiedArguments[option + 1] = path
            return try execute(arguments: copiedArguments)
        }
    }

    private func execute(arguments: [String]) throws -> (output: Data, error: Data, status: Int32) {
        let capture = try CaptureFiles()
        defer { capture.remove() }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
        process.arguments = arguments
        process.standardOutput = capture.output
        process.standardError = capture.error
        try process.run()
        process.waitUntilExit()
        capture.close()
        return try (capture.outputData(), capture.errorData(), process.terminationStatus)
    }
}
