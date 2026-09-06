@testable import CrapCLI
import Foundation
import Testing

struct XcodeResultBundleCopyTests {
    @Test func `reader cache cannot change original evidence`() throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let original = directory.appendingPathComponent("Tests.xcresult")
        try FileManager.default.createDirectory(at: original, withIntermediateDirectories: false)
        try Data("evidence".utf8).write(to: original.appendingPathComponent("Data"))
        let before = try ArtifactDigest().read(at: original.path)

        let copy = try XcodeResultBundleCopy().read(at: original.path) { path in
            try Data("reader cache".utf8)
                .write(to: URL(fileURLWithPath: path).appendingPathComponent("database.sqlite3"))
            return path
        }

        #expect(try ArtifactDigest().read(at: original.path) == before)
        #expect(!FileManager.default.fileExists(atPath: copy))
    }

    @Test func `failed read removes private copy`() throws {
        let original = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: original) }
        var copiedPath: String?

        #expect(throws: CopyTestError.failed) {
            try XcodeResultBundleCopy().read(at: original.path) { path in
                copiedPath = path
                throw CopyTestError.failed
            }
        }

        let copy = try #require(copiedPath)
        #expect(!FileManager.default.fileExists(atPath: copy))
        #expect(FileManager.default.fileExists(atPath: original.path))
    }

    private func makeDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        return directory
    }
}

private enum CopyTestError: Error {
    case failed
}
