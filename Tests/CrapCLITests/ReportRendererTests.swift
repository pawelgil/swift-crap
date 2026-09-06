@testable import CrapCLI
import CrapCore
import Foundation
import Testing

struct ReportRendererTests {
    @Test func `json is deterministic with sorted schema keys`() throws {
        let report = makeReport()
        let sut = createSUT()

        let first = try sut.render(report, as: .json)
        let second = try sut.render(report, as: .json)

        #expect(first == second)
        #expect(first.last == 0x0A)
        #expect(try JSONDecoder().decode(AnalysisReport.self, from: first) == report)
        let output = String(decoding: first, as: UTF8.self)
        let functions = try #require(output.range(of: "\"functions\"")?.lowerBound)
        let metric = try #require(output.range(of: "\"metric\"")?.lowerBound)
        let schema = try #require(output.range(of: "\"schemaVersion\"")?.lowerBound)
        let summary = try #require(output.range(of: "\"summary\"")?.lowerBound)
        #expect(functions < metric && metric < schema && schema < summary)
    }

    @Test func `text renders stable summary`() throws {
        let sut = createSUT()

        let data = try sut.render(makeReport(), as: .text)

        #expect(String(decoding: data, as: UTF8.self) == """
        metric: crap-line-v1
        verification: library-unverified
        threshold: 30
        functions: 0
        measured: 0
        assumed: 0
        violations: 0

        """)
    }

    @Test func `text identifies the captured build`() throws {
        let report = AnalysisReport(
            functions: [],
            summary: makeReport().summary,
            verification: "captured",
            buildIdentity: "abc123",
        )

        let data = try createSUT().render(report, as: .text)

        #expect(String(decoding: data, as: UTF8.self).contains("build-identity: abc123\n"))
    }

    private func createSUT() -> ReportRenderer {
        ReportRenderer()
    }

    private func makeReport() -> AnalysisReport {
        AnalysisReport(
            functions: [],
            summary: ReportSummary(
                totalFunctions: 0,
                measuredFunctions: 0,
                assumedFunctions: 0,
                violations: 0,
                threshold: 30,
            ),
        )
    }
}
