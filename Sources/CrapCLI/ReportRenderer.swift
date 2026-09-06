import CrapCore
import Foundation

struct ReportRenderer {
    func render(_ report: AnalysisReport, as format: OutputFormat) throws -> Data {
        switch format {
        case .json:
            try json(report)
        case .text:
            Data(text(report).utf8)
        }
    }

    private func json(_ report: AnalysisReport) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        var data = try encoder.encode(report)
        data.append(0x0A)
        return data
    }

    private func text(_ report: AnalysisReport) -> String {
        var lines = [
            "metric: \(report.metric)",
            "verification: \(report.verification ?? "library-unverified")",
            "threshold: \(number(report.summary.threshold))",
            "functions: \(report.summary.totalFunctions)",
            "measured: \(report.summary.measuredFunctions)",
            "assumed: \(report.summary.assumedFunctions)",
            "violations: \(report.summary.violations)",
        ]
        if let buildIdentity = report.buildIdentity {
            lines.insert("build-identity: \(buildIdentity)", at: 2)
        }
        lines.append(contentsOf: report.functions.map(function))
        return lines.joined(separator: "\n") + "\n"
    }

    private func function(_ score: FunctionScore) -> String {
        let position = score.callable.span.start
        return "\(score.callable.file):\(position.line):\(position.column) \(score.callable.name) complexity=\(score.callable.complexity) coverage=\(number(score.coverage)) crap=\(number(score.crap)) status=\(score.coverageStatus)"
    }

    private func number(_ value: Double) -> String {
        String(format: "%.6g", locale: Locale(identifier: "en_US_POSIX"), value)
    }
}
