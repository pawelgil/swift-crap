import CrapApplication
import CrapCore
import Foundation
import Testing

struct AnalyzeProjectTests {
    @Test func `analyzes selected sources with imported coverage`() throws {
        let callable = makeCallable()
        let coverage = makeCoverage()
        let sut = createSUT(callables: [callable], coverage: [coverage])

        let report = try sut.execute(makeRequest())

        #expect(report.functions.map(\.callable) == [callable])
        #expect(report.summary.measuredFunctions == 1)
    }

    @Test func `repeated coverage files are combined`() throws {
        let sut = createSUT(callables: [makeCallable()], coverage: [makeCoverage()])

        let report = try sut.execute(makeRequest(coverageFiles: ["one.json", "two.json"]))

        #expect(report.summary.measuredFunctions == 1)
    }

    @Test func `missing coverage input is rejected`() {
        let sut = createSUT()

        #expect(throws: AnalysisFailure.noCoverageFiles) {
            try sut.execute(makeRequest(coverageFiles: []))
        }
    }

    @Test func `empty source selection is rejected`() {
        let sut = createSUT(sources: [])

        #expect(throws: AnalysisFailure.noSources) {
            try sut.execute(makeRequest())
        }
    }

    @Test func `source without callables is rejected`() {
        let sut = createSUT(callables: [])

        #expect(throws: AnalysisFailure.noCallables) {
            try sut.execute(makeRequest())
        }
    }

    @Test func `non utf8 source is rejected`() {
        let sut = createSUT(sourceData: Data([0xFF]))

        #expect(throws: AnalysisFailure.invalidSourceEncoding("/repo/Foo.swift")) {
            try sut.execute(makeRequest())
        }
    }

    @Test func `malformed baseline is rejected`() {
        let sut = createSUT(files: ["baseline.json": Data("bad".utf8)])

        #expect(throws: AnalysisFailure.invalidBaseline("baseline.json")) {
            try sut.execute(makeRequest(baselineFile: "baseline.json"))
        }
    }

    @Test func `malformed coverage identifies artifact`() {
        let sut = createSUT(coverageFails: true)

        #expect(throws: AnalysisFailure.invalidCoverage(file: "coverage.json", reason: "invalidCoverage")) {
            try sut.execute(makeRequest())
        }
    }

    @Test func `coverage read failure identifies artifact`() {
        let sut = createSUT()

        #expect(throws: AnalysisFailure.invalidCoverage(file: "absent.json", reason: "missingFile")) {
            try sut.execute(makeRequest(coverageFiles: ["absent.json"]))
        }
    }

    @Test func `source analyzer failure identifies artifact`() {
        let sut = createSUT(sourceAnalysisFails: true)

        #expect(throws: AnalysisFailure.invalidSource(file: "/repo/Foo.swift", reason: "invalidSource")) {
            try sut.execute(makeRequest())
        }
    }

    private func createSUT(
        sources: [SelectedSource] = [SelectedSource(path: "/repo/Foo.swift", relativePath: "Foo.swift")],
        sourceData: Data = Data("func foo() {}".utf8),
        files: [String: Data] = [:],
        callables: [Callable]? = nil,
        coverage: [CoverageRecord]? = nil,
        coverageFails: Bool = false,
        sourceAnalysisFails: Bool = false,
    ) -> AnalyzeProject {
        var availableFiles = [
            "/repo/Foo.swift": sourceData,
            "coverage.json": Data(),
            "one.json": Data(),
            "two.json": Data(),
        ]
        availableFiles.merge(files) { _, new in new }
        return AnalyzeProject(
            sourceSelector: StubSourceSelector(result: SelectedSources(root: "/repo", files: sources)),
            fileReader: StubFileReader(files: availableFiles),
            sourceAnalyzer: StubSourceAnalyzer(
                callables: callables ?? [makeCallable()],
                fails: sourceAnalysisFails,
            ),
            coverageDecoder: StubCoverageDecoder(records: coverage ?? [makeCoverage()], fails: coverageFails),
        )
    }

    private func makeRequest(
        coverageFiles: [String] = ["coverage.json"],
        baselineFile: String? = nil,
    ) -> AnalysisRequest {
        AnalysisRequest(
            selection: SourceSelectionRequest(scope: .project("/repo")),
            coverageFiles: coverageFiles,
            baselineFile: baselineFile,
        )
    }

    private func makeCallable() -> Callable {
        Callable(
            id: "Foo.swift::foo()::function",
            file: "Foo.swift",
            name: "foo()",
            kind: .function,
            span: makeSpan(),
            bodySpan: makeSpan(),
            complexity: 1,
            parentID: nil,
        )
    }

    private func makeCoverage() -> CoverageRecord {
        CoverageRecord(
            file: "/repo/Foo.swift",
            name: "foo()",
            span: makeSpan(),
            anchor: SourcePosition(line: 1, column: 1),
            lines: [CoverageLine(line: 1, covered: true)],
            coveredLines: nil,
            executableLines: nil,
        )
    }

    private func makeSpan() -> SourceSpan {
        SourceSpan(start: SourcePosition(line: 1, column: 1), end: SourcePosition(line: 1, column: 14))
    }
}

private struct StubSourceSelector: SourceSelecting {
    let result: SelectedSources

    func select(_: SourceSelectionRequest) throws -> SelectedSources {
        result
    }
}

private struct StubFileReader: FileReading {
    let files: [String: Data]

    func read(at path: String) throws -> Data {
        guard let data = files[path] else {
            throw StubError.missingFile
        }
        return data
    }
}

private struct StubSourceAnalyzer: SourceAnalyzing {
    let callables: [Callable]
    let fails: Bool

    func analyze(source _: String, file _: String) throws -> [Callable] {
        if fails {
            throw StubError.invalidSource
        }
        return callables
    }
}

private struct StubCoverageDecoder: CoverageDecoding {
    let records: [CoverageRecord]
    let fails: Bool

    func decode(_: Data) throws -> CoverageImport {
        if fails {
            throw StubError.invalidCoverage
        }
        return CoverageImport(records: records, format: "test")
    }
}

private enum StubError: Error {
    case invalidCoverage
    case invalidSource
    case missingFile
}
