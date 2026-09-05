import CrapCore
import Testing

struct MetricContractTests {
    @Test(arguments: [
        (complexity: 1, covered: 0, executable: 1, expected: 2.0),
        (complexity: 5, covered: 0, executable: 2, expected: 30.0),
        (complexity: 5, covered: 1, executable: 2, expected: 8.125),
        (complexity: 5, covered: 2, executable: 2, expected: 5.0),
    ])
    func `formula uses complexity and coverage`(
        complexity: Int, covered: Int, executable: Int, expected: Double,
    ) throws {
        let report = try evaluate(complexity: complexity, covered: covered, executable: executable)

        #expect(report.functions.first?.crap == expected)
    }

    @Test func `score equal to threshold passes`() throws {
        let report = try evaluate(complexity: 5, covered: 0, executable: 1, threshold: 30)

        #expect(report.summary.violations == 0)
    }

    @Test func `score strictly above threshold fails`() throws {
        let report = try evaluate(complexity: 5, covered: 0, executable: 1, threshold: 29.999)

        #expect(report.summary.violations == 1)
    }

    private func evaluate(
        complexity: Int, covered: Int, executable: Int, threshold: Double = 30,
    ) throws -> AnalysisReport {
        let span = SourceSpan(start: .init(line: 1, column: 1), end: .init(line: 10, column: 2))
        let callable = Callable(
            id: "subject", file: "Subject.swift", name: "subject()", kind: .function,
            span: span, bodySpan: span, complexity: complexity, parentID: nil,
        )
        let coverage = CoverageRecord(
            file: "Subject.swift", name: "subject()", span: nil, anchor: span.start,
            lines: nil, coveredLines: covered, executableLines: executable,
        )
        return try AnalysisEngine().analyze(
            callables: [callable], coverage: [coverage], root: "/project",
            missing: .error, threshold: threshold,
        )
    }
}
