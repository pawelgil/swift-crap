import Foundation

struct XCCovExporter: XCCovExporting {
    func report(at path: String) throws -> Data {
        let capture = try CaptureFiles()
        defer { capture.remove() }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
        process.arguments = ["xccov", "view", "--report", "--json", path]
        process.standardOutput = capture.output
        process.standardError = capture.error
        try process.run()
        process.waitUntilExit()
        capture.close()
        guard process.terminationStatus == 0 else {
            let message = try String(decoding: capture.errorData(), as: UTF8.self)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            throw XCCovExportError.commandFailed(message)
        }
        return try capture.outputData()
    }
}
