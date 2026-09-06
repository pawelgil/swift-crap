import CrapCore
import Testing

struct AnalysisValidationTests {
    @Test func `empty callable inventory throws`() {
        #expect(throws: AnalysisError.emptyCallableInventory) {
            try Self.analyze(callables: [], coverage: [])
        }
    }

    @Test func `empty root throws`() {
        #expect(throws: AnalysisError.invalidRoot) {
            try Self.analyze(root: "")
        }
    }

    @Test func `duplicate callable identifiers throw`() {
        let callable = Self.makeCallable()

        #expect(throws: AnalysisError.duplicateCallableID(callable.id)) {
            try Self.analyze(callables: [callable, callable])
        }
    }

    @Test func `duplicate baseline identifiers throw`() {
        let score = Self.makeScore()
        let baseline = Self.makeBaseline(
            functions: [score, score],
            summary: Self.makeSummary(total: 2, measured: 2),
        )

        #expect(throws: AnalysisError.duplicateBaselineID(score.callable.id)) {
            try Self.analyze(baseline: baseline)
        }
    }

    @Test func `mixed coverage representations throw`() {
        let lineCoverage = Self.makeLineCoverage()
        let aggregateCoverage = Self.makeAggregateCoverage()

        #expect(throws: AnalysisError.mixedCoverageRepresentations(callableID: "callable")) {
            try Self.analyze(coverage: [lineCoverage, aggregateCoverage])
        }
    }

    @Test(arguments: InvalidCallableCase.allCases)
    func `invalid callable primitives throw`(_ invalidCase: InvalidCallableCase) {
        let callable = invalidCase.callable()

        #expect(throws: AnalysisError.invalidCallable(callable.id)) {
            try Self.analyze(callables: [callable])
        }
    }

    @Test(arguments: InvalidCoverageCase.allCases)
    func `invalid coverage primitives throw`(_ invalidCase: InvalidCoverageCase) {
        let coverage = invalidCase.coverage()

        #expect(throws: AnalysisError.invalidCoverage(recordName: coverage.name, file: coverage.file)) {
            try Self.analyze(coverage: [coverage])
        }
    }

    @Test(arguments: InvalidBaselineCase.allCases)
    func `invalid baseline contents throw`(_ invalidCase: InvalidBaselineCase) {
        #expect(throws: AnalysisError.incompatibleBaseline) {
            try Self.analyze(baseline: invalidCase.baseline())
        }
    }

    private static func analyze(
        callables: [Callable] = [AnalysisValidationTests.makeCallable()],
        coverage: [CoverageRecord] = [AnalysisValidationTests.makeAggregateCoverage()],
        root: String = "/workspace",
        baseline: AnalysisReport? = nil,
    ) throws -> AnalysisReport {
        try AnalysisEngine().analyze(
            callables: callables,
            coverage: coverage,
            root: root,
            missing: .error,
            threshold: 30,
            baseline: baseline,
        )
    }

    private static func makeAggregateCoverage(
        covered: Int? = 1,
        executable: Int? = 1,
    ) -> CoverageRecord {
        CoverageRecord(
            file: "/workspace/Feature.swift",
            name: "feature()",
            span: nil,
            anchor: SourcePosition(line: 1, column: 1),
            lines: nil,
            coveredLines: covered,
            executableLines: executable,
        )
    }

    private static func makeBaseline(
        functions: [FunctionScore] = [AnalysisValidationTests.makeScore()],
        summary: ReportSummary = AnalysisValidationTests.makeSummary(),
    ) -> AnalysisReport {
        AnalysisReport(functions: functions, summary: summary)
    }

    private static func makeCallable(
        id: String = "callable",
        file: String = "Feature.swift",
        name: String = "feature()",
        span: SourceSpan = AnalysisValidationTests.makeSpan(startLine: 1, endLine: 4),
        bodySpan: SourceSpan = AnalysisValidationTests.makeSpan(startLine: 1, endLine: 4),
        complexity: Int = 1,
    ) -> Callable {
        Callable(
            id: id,
            file: file,
            name: name,
            kind: .function,
            span: span,
            bodySpan: bodySpan,
            complexity: complexity,
            parentID: nil,
        )
    }

    private static func makeLineCoverage(
        lines: [CoverageLine] = [CoverageLine(line: 1, covered: true)],
    ) -> CoverageRecord {
        CoverageRecord(
            file: "/workspace/Feature.swift",
            name: "feature()",
            span: makeSpan(startLine: 1, endLine: 4),
            anchor: SourcePosition(line: 1, column: 1),
            lines: lines,
            coveredLines: nil,
            executableLines: nil,
        )
    }

    private static func makeScore(crap: Double = 2) -> FunctionScore {
        FunctionScore(
            callable: makeCallable(),
            coveredLines: 0,
            executableLines: 1,
            coverage: 0,
            crap: crap,
            coverageStatus: "measured",
        )
    }

    private static func makeSpan(startLine: Int, endLine: Int) -> SourceSpan {
        SourceSpan(
            start: SourcePosition(line: startLine, column: 1),
            end: SourcePosition(line: endLine, column: 1),
        )
    }

    private static func makeSummary(total: Int = 1, measured: Int = 1) -> ReportSummary {
        ReportSummary(
            totalFunctions: total,
            measuredFunctions: measured,
            assumedFunctions: 0,
            violations: 0,
            threshold: 30,
        )
    }

    enum InvalidBaselineCase: CaseIterable {
        case score
        case summary

        func baseline() -> AnalysisReport {
            switch self {
            case .score:
                AnalysisValidationTests.makeBaseline(functions: [AnalysisValidationTests.makeScore(crap: 999)])
            case .summary:
                AnalysisValidationTests.makeBaseline(summary: AnalysisValidationTests.makeSummary(total: 2))
            }
        }
    }

    enum InvalidCallableCase: CaseIterable {
        case absolutePath
        case bodyOutsideSpan
        case emptyID
        case emptyName
        case invalidSpan
        case nonNormalizedPath
        case zeroComplexity

        func callable() -> Callable {
            switch self {
            case .absolutePath:
                AnalysisValidationTests.makeCallable(file: "/workspace/Feature.swift")
            case .bodyOutsideSpan:
                AnalysisValidationTests.makeCallable(
                    bodySpan: AnalysisValidationTests.makeSpan(startLine: 1, endLine: 5),
                )
            case .emptyID:
                AnalysisValidationTests.makeCallable(id: "")
            case .emptyName:
                AnalysisValidationTests.makeCallable(name: "")
            case .invalidSpan:
                AnalysisValidationTests.makeCallable(
                    span: AnalysisValidationTests.makeSpan(startLine: 2, endLine: 1),
                )
            case .nonNormalizedPath:
                AnalysisValidationTests.makeCallable(file: "Sources/../Feature.swift")
            case .zeroComplexity:
                AnalysisValidationTests.makeCallable(complexity: 0)
            }
        }
    }

    enum InvalidCoverageCase: CaseIterable {
        case coveredExceedsExecutable
        case duplicateLine
        case missingAggregateCount
        case negativeAggregateCount
        case nonpositiveLine

        func coverage() -> CoverageRecord {
            switch self {
            case .coveredExceedsExecutable:
                AnalysisValidationTests.makeAggregateCoverage(covered: 2, executable: 1)
            case .duplicateLine:
                AnalysisValidationTests.makeLineCoverage(lines: [
                    CoverageLine(line: 1, covered: true),
                    CoverageLine(line: 1, covered: false),
                ])
            case .missingAggregateCount:
                AnalysisValidationTests.makeAggregateCoverage(covered: nil)
            case .negativeAggregateCount:
                AnalysisValidationTests.makeAggregateCoverage(covered: -1)
            case .nonpositiveLine:
                AnalysisValidationTests.makeLineCoverage(lines: [CoverageLine(line: 0, covered: false)])
            }
        }
    }
}
