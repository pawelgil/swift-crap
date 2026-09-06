import CrapApplication
import Foundation

struct CapturedCoverageFileReader: FileReading {
    private let exports: CapturedCoverageExports
    private let fallback: any FileReading

    init(exports: [String: Data], fallback: any FileReading) throws {
        self.exports = try CapturedCoverageExports(exports)
        self.fallback = fallback
    }

    func read(at path: String) throws -> Data {
        let canonical = try CanonicalPath().resolve(path)
        if let data = exports.values[canonical] { return data }
        return try fallback.read(at: path)
    }
}
