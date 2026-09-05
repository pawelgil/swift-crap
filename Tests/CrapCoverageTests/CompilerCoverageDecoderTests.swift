import CrapCore
import CrapCoverage
import Foundation
import Testing

struct CompilerCoverageDecoderTests {
    @Test func `llvm regions produce per function line coverage`() throws {
        let data = llvmData(regions: [
            [2, 3, 4, 1, 0, 0, 0, 0],
            [3, 1, 3, 12, 4, 0, 0, 0],
        ])
        let sut = createSUT()

        let result = try sut.decode(data)

        let record = try #require(result.records.first)
        #expect(result.format == "llvm")
        #expect(record.file == "/workspace/Feature.swift")
        #expect(record.name == "feature()")
        #expect(record.anchor == SourcePosition(line: 2, column: 3))
        #expect(record.lines == [
            CoverageLine(line: 2, covered: false),
            CoverageLine(line: 3, covered: true),
            CoverageLine(line: 4, covered: false),
        ])
    }

    @Test func `llvm uses maximum region entry count on line`() throws {
        let data = llvmData(regions: [
            [2, 1, 2, 20, 0, 0, 0, 0],
            [2, 5, 2, 10, 1, 0, 0, 0],
        ])
        let sut = createSUT()

        let result = try sut.decode(data)

        #expect(result.records.first?.lines == [CoverageLine(line: 2, covered: true)])
    }

    @Test func `narrower LLVM region overrides broad executed region`() throws {
        let data = llvmData(regions: [
            [2, 1, 5, 1, 1, 0, 0, 0],
            [3, 1, 4, 1, 0, 0, 0, 0],
        ])
        let sut = createSUT()

        let result = try sut.decode(data)

        #expect(result.records.first?.lines == [
            CoverageLine(line: 2, covered: true),
            CoverageLine(line: 3, covered: true),
            CoverageLine(line: 4, covered: false),
            CoverageLine(line: 5, covered: true),
        ])
    }

    @Test func `code region wins over expansion with identical span`() throws {
        let data = llvmData(regions: [
            [2, 1, 2, 20, 0, 0, 0, 0],
            [2, 1, 2, 20, 1, 0, 0, 1],
        ])
        let sut = createSUT()

        let result = try sut.decode(data)

        #expect(result.records.first?.lines == [CoverageLine(line: 2, covered: false)])
    }

    @Test func `identical code regions combine counts`() throws {
        let data = llvmData(regions: [
            [2, 1, 2, 20, 0, 0, 0, 0],
            [2, 1, 2, 20, 1, 0, 0, 0],
        ])
        let sut = createSUT()

        let result = try sut.decode(data)

        #expect(result.records.first?.lines == [CoverageLine(line: 2, covered: true)])
    }

    @Test func `llvm uses each region file index`() throws {
        let data = llvmData(
            filenames: ["/workspace/One.swift", "/workspace/Two.swift"],
            regions: [
                [2, 1, 2, 8, 1, 0, 0, 0],
                [8, 1, 8, 8, 0, 1, 0, 0],
            ],
        )
        let sut = createSUT()

        let result = try sut.decode(data)

        #expect(result.records.map(\.file) == ["/workspace/One.swift", "/workspace/Two.swift"])
        #expect(result.records.map(\.lines) == [
            [CoverageLine(line: 2, covered: true)],
            [CoverageLine(line: 8, covered: false)],
        ])
    }

    @Test func `xccov functions produce aggregate coverage`() throws {
        let data = xccovData()
        let sut = createSUT()

        let result = try sut.decode(data)

        let record = try #require(result.records.first)
        #expect(result.format == "xccov")
        #expect(record.file == "/workspace/Feature.swift")
        #expect(record.anchor == SourcePosition(line: 7, column: 1))
        #expect(record.coveredLines == 2)
        #expect(record.executableLines == 3)
        #expect(record.lines == nil)
    }

    @Test func `relative coverage paths remain relative`() throws {
        let data = xccovData(file: "Sources/../Sources/Feature.swift")
        let sut = createSUT()

        let result = try sut.decode(data)

        #expect(result.records.first?.file == "Sources/Feature.swift")
    }

    @Test func `unsupported LLVM version throws`() {
        let data = llvmData(version: "4.0.0")
        let sut = createSUT()

        #expect(throws: CoverageDecodingError.unsupportedLLVMVersion("4.0.0")) {
            try sut.decode(data)
        }
    }

    @Test func `invalid LLVM region throws`() {
        let data = llvmData(regions: [[2, 1, 1, 1, 0, 0, 0, 0]])
        let sut = createSUT()

        #expect(throws: CoverageDecodingError.malformedInput) {
            try sut.decode(data)
        }
    }

    @Test func `oversized LLVM line range throws`() {
        let data = llvmData(regions: [[1, 1, Int.max, 1, 1, 0, 0, 0]])
        let sut = createSUT()

        #expect(throws: CoverageDecodingError.oversizedLineRange(maximumExpandedLines: 1_000_000)) {
            try sut.decode(data)
        }
    }

    @Test func `inconsistent xccov fraction throws`() {
        let data = xccovData(lineCoverage: 1)
        let sut = createSUT()

        #expect(throws: CoverageDecodingError.invalidCounts) {
            try sut.decode(data)
        }
    }

    @Test func `covered lines cannot exceed executable lines`() {
        let data = xccovData(covered: 4, executable: 3, lineCoverage: 4.0 / 3.0)
        let sut = createSUT()

        #expect(throws: CoverageDecodingError.invalidCounts) {
            try sut.decode(data)
        }
    }

    @Test func `unknown JSON shape throws`() throws {
        let data = try #require("{\"functions\":[]}".data(using: .utf8))
        let sut = createSUT()

        #expect(throws: CoverageDecodingError.unsupportedSchema) {
            try sut.decode(data)
        }
    }

    private func createSUT() -> CompilerCoverageDecoder {
        CompilerCoverageDecoder()
    }

    private func llvmData(
        version: String = "2.0.1",
        filenames: [String] = ["/workspace/Feature.swift"],
        regions: [[Int]] = [[2, 1, 2, 8, 1, 0, 0, 0]],
    ) -> Data {
        let function: [String: Any] = [
            "count": 1,
            "name": "feature()",
            "filenames": filenames,
            "regions": regions,
        ]
        let object: [String: Any] = [
            "type": "llvm.coverage.json.export",
            "version": version,
            "data": [["functions": [function]]],
        ]
        return try! JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
    }

    private func xccovData(
        file: String = "/workspace/Feature.swift",
        covered: Int = 2,
        executable: Int = 3,
        lineCoverage: Double = 2.0 / 3.0,
    ) -> Data {
        let function: [String: Any] = [
            "name": "feature()",
            "lineNumber": 7,
            "executionCount": 1,
            "coveredLines": covered,
            "executableLines": executable,
            "lineCoverage": lineCoverage,
        ]
        let fileObject: [String: Any] = [
            "name": file,
            "coveredLines": covered,
            "executableLines": executable,
            "lineCoverage": lineCoverage,
            "functions": [function],
        ]
        let target: [String: Any] = [
            "name": "App",
            "coveredLines": covered,
            "executableLines": executable,
            "lineCoverage": lineCoverage,
            "files": [fileObject],
        ]
        let object: [String: Any] = [
            "coveredLines": covered,
            "executableLines": executable,
            "lineCoverage": lineCoverage,
            "targets": [target],
        ]
        return try! JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
    }
}
