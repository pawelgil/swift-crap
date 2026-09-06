@testable import CrapCLI
import CrapCore
import Testing

struct CLIDiagnosticFormatterTests {
    @Test(arguments: [0, 2])
    func `assumed coverage warning is independent of gate result`(violations: Int) {
        let report = makeReport(statuses: ["assumedZero", "assumedZero"], violations: violations)

        let warning = createSUT().warning(for: report)

        #expect(warning == assumedZeroWarning(count: 2))
    }

    @Test func `measured zero coverage has no warning`() {
        let report = makeReport(statuses: ["measured"])

        let warning = createSUT().warning(for: report)

        #expect(warning == nil)
    }

    @Test func `missing coverage retains error and adds actionable hint`() {
        let id = "Sources/Feature.swift::function::run()"

        let message = createSUT().message(for: AnalysisError.missingCoverage(callableID: id))

        #expect(message == """
        Missing coverage for source callable Sources/Feature.swift::function::run().
        hint: Missing records may result from compiler omission or incomplete build/coverage inputs. See https://github.com/pawelgil/swift-crap#missing-compiler-coverage
        """)
    }

    @Test func `unrelated analysis error remains unchanged`() {
        let message = createSUT().message(for: AnalysisError.invalidThreshold)

        #expect(message == "CRAP threshold must be finite and nonnegative.")
    }

    private func createSUT() -> CLIDiagnosticFormatter {
        CLIDiagnosticFormatter()
    }

    private func makeReport(statuses: [String], violations: Int = 0) -> AnalysisReport {
        let scores = statuses.enumerated().map { index, status in
            FunctionScore(
                callable: makeCallable(index: index),
                coveredLines: 0,
                executableLines: status == "measured" ? 1 : 0,
                coverage: 0,
                crap: 2,
                coverageStatus: status,
            )
        }
        return AnalysisReport(
            functions: scores,
            summary: ReportSummary(
                totalFunctions: scores.count,
                measuredFunctions: scores.count { $0.coverageStatus == "measured" },
                assumedFunctions: scores.count { $0.coverageStatus == "assumedZero" },
                violations: violations,
                threshold: 30,
            ),
        )
    }

    private func makeCallable(index: Int) -> Callable {
        let position = SourcePosition(line: index + 1, column: 1)
        let span = SourceSpan(start: position, end: SourcePosition(line: index + 1, column: 2))
        return Callable(
            id: "Sources/Feature.swift::function::run\(index)()",
            file: "Sources/Feature.swift",
            name: "run\(index)()",
            kind: .function,
            span: span,
            bodySpan: span,
            complexity: 1,
            parentID: nil,
        )
    }

    private func assumedZeroWarning(count: Int) -> String {
        "warning: assumed-zero coverage affects \(count) functions; affected scores assume zero coverage and are NOT measured. Missing records may result from compiler omission or incomplete build/coverage inputs. See https://github.com/pawelgil/swift-crap#missing-compiler-coverage"
    }
}
