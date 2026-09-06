import CrapApplication
import CrapCore

struct CLIDiagnosticFormatter {
    func warning(for report: AnalysisReport) -> String? {
        let count = report.functions.count { $0.coverageStatus == "assumedZero" }
        guard count > 0 else { return nil }
        let label = count == 1 ? "function" : "functions"
        return "warning: assumed-zero coverage affects \(count) \(label); affected scores assume zero coverage and are NOT measured. Missing records may result from compiler omission or incomplete build/coverage inputs. See \(Self.missingCoverageURL)"
    }

    func message(for error: Error) -> String {
        let message = baseMessage(for: error)
        guard let analysisError = error as? AnalysisError,
              case .missingCoverage = analysisError
        else { return message }
        return "\(message)\nhint: Missing records may result from compiler omission or incomplete build/coverage inputs. See \(Self.missingCoverageURL)"
    }

    private func baseMessage(for error: Error) -> String {
        guard let error = error as? AnalysisFailure else { return String(describing: error) }
        return switch error {
        case let .invalidBaseline(path): "invalid baseline: \(path)"
        case let .invalidCoverage(file, reason): "invalid coverage \(file): \(reason)"
        case let .invalidSource(file, reason): "invalid source \(file): \(reason)"
        case let .invalidSourceEncoding(path): "source is not UTF-8: \(path)"
        case .noCallables: "no callable inventory"
        case .noCoverageFiles: "no coverage files"
        case .noSources: "no usable sources"
        }
    }

    private static let missingCoverageURL = "https://github.com/pawelgil/swift-crap#missing-compiler-coverage"
}
