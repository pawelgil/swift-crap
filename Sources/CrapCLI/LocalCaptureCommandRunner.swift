import CrapApplication
import Foundation

struct LocalCaptureCommandRunner: CaptureCommandRunning {
    func run(_ command: [String], root: String) throws {
        guard !command.isEmpty else {
            throw ProvenanceError.invalid("capture requires an explicit command after --")
        }
        let capture = try CaptureFiles()
        defer { capture.remove() }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = command
        process.currentDirectoryURL = URL(fileURLWithPath: root)
        process.standardOutput = capture.output
        process.standardError = capture.error
        try process.run()
        process.waitUntilExit()
        capture.close()
        try FileHandle.standardError.write(capture.outputData())
        try FileHandle.standardError.write(capture.errorData())
        guard process.terminationStatus == 0 else {
            throw ProvenanceError.invalid("capture command failed with exit \(process.terminationStatus)")
        }
    }
}
