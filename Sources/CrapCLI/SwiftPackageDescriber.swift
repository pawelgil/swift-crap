import Foundation

struct SwiftPackageDescriber: PackageDescribing {
    func describe(packageAt path: String) throws -> PackageMetadata {
        let capture = try CaptureFiles()
        defer { capture.remove() }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = [
            "swift", "package",
            "--package-path", path,
            "--scratch-path", capture.scratchURL.path,
            "--cache-path", capture.cacheURL.path,
            "--disable-automatic-resolution",
            "describe", "--type", "json",
        ]
        process.standardOutput = capture.output
        process.standardError = capture.error
        try process.run()
        process.waitUntilExit()
        capture.close()
        let error = try capture.errorData()
        guard process.terminationStatus == 0 else {
            let message = String(decoding: error, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
            throw SourceSelectionError.packageDescription(message)
        }
        do {
            return try JSONDecoder().decode(PackageMetadata.self, from: capture.outputData())
        } catch {
            throw SourceSelectionError.invalidPackageMetadata
        }
    }
}
