import CrapApplication
@testable import CrapCLI
import Foundation
import Testing

struct CapturedCoverageFileReaderTests {
    @Test func `captured result reads frozen bytes without build products`() throws {
        let path = "/removed/build/Tests.xcresult"
        let expected = Data("frozen native coverage".utf8)
        let sut = try CapturedCoverageFileReader(exports: [path: expected], fallback: UnusedFileReader())

        let result = try sut.read(at: path)

        #expect(result == expected)
    }

    @Test func `canonical path alias reads captured bytes`() throws {
        let expected = Data("frozen native coverage".utf8)
        let sut = try CapturedCoverageFileReader(
            exports: ["/build/Tests.xcresult": expected],
            fallback: UnusedFileReader(),
        )

        let result = try sut.read(at: "/build/./Tests.xcresult")

        #expect(result == expected)
    }

    @Test func `uncaptured file uses ordinary reader`() throws {
        let expected = Data("source text".utf8)
        let sut = try CapturedCoverageFileReader(exports: [:], fallback: StubFileReader(data: expected))

        let result = try sut.read(at: "/repo/File.swift")

        #expect(result == expected)
    }

    @Test func `duplicate canonical exports are rejected`() {
        let exports = ["/build/Tests.xcresult": Data([1]), "/build/./Tests.xcresult": Data([2])]

        #expect(throws: ProvenanceError.invalid("capture contains duplicate coverage export paths")) {
            _ = try CapturedCoverageFileReader(exports: exports, fallback: UnusedFileReader())
        }
    }

    @Test func `empty captured export cannot fall back to mutable data`() {
        #expect(throws: ProvenanceError.invalid("capture contains empty coverage export")) {
            _ = try CapturedCoverageFileReader(
                exports: ["/build/Tests.xcresult": Data()],
                fallback: UnusedFileReader(),
            )
        }
    }
}

private struct UnusedFileReader: FileReading {
    func read(at _: String) throws -> Data {
        throw CocoaError(.fileReadNoSuchFile)
    }
}

private struct StubFileReader: FileReading {
    let data: Data

    func read(at _: String) -> Data {
        data
    }
}
