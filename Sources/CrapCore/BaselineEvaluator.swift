struct BaselineEvaluator {
    private let functionScoring = FunctionScoring()
    private let validator = AnalysisInputValidator()

    func validatedScores(from baseline: AnalysisReport?) throws -> [String: Double]? {
        guard let baseline else {
            return nil
        }
        guard baseline.schemaVersion == 1, baseline.metric == "crap-line-v1" else {
            throw AnalysisError.incompatibleBaseline
        }
        try validateFunctions(baseline.functions)
        guard valid(summary: baseline.summary, scores: baseline.functions) else {
            throw AnalysisError.incompatibleBaseline
        }
        return Dictionary(uniqueKeysWithValues: baseline.functions.map { ($0.callable.id, $0.crap) })
    }

    func violationCount(
        scores: [FunctionScore],
        threshold: Double,
        baseline: [String: Double]?,
    ) -> Int {
        scores.count { score in
            guard let baseline else {
                return score.crap > threshold
            }
            guard let previous = baseline[score.callable.id] else {
                return score.crap > threshold
            }
            return score.crap > previous
        }
    }

    private func validateFunctions(_ scores: [FunctionScore]) throws {
        if !scores.isEmpty {
            do {
                try validator.validateCallableSet(scores.map(\.callable))
            } catch let error as AnalysisError {
                if case let .duplicateCallableID(id) = error {
                    throw AnalysisError.duplicateBaselineID(id)
                }
                throw AnalysisError.incompatibleBaseline
            }
        }
        guard scores.allSatisfy(valid) else {
            throw AnalysisError.incompatibleBaseline
        }
    }

    private func valid(_ score: FunctionScore) -> Bool {
        guard score.coveredLines >= 0,
              score.executableLines >= 0,
              score.coveredLines <= score.executableLines,
              score.coverage.isFinite,
              score.crap.isFinite,
              score.coverage >= 0,
              score.coverage <= 1,
              score.coverageStatus == "measured" || score.coverageStatus == "assumedZero",
              score.coverageStatus != "assumedZero" || score.coveredLines == 0 && score.executableLines == 0
        else {
            return false
        }
        let measurement = CoverageMeasurement(covered: score.coveredLines, executable: score.executableLines)
        return functionScoring.score(
            callable: score.callable,
            measurement: measurement,
            status: score.coverageStatus,
        ) == score
    }

    private func valid(summary: ReportSummary, scores: [FunctionScore]) -> Bool {
        let measured = scores.count { $0.coverageStatus == "measured" }
        let assumed = scores.count { $0.coverageStatus == "assumedZero" }
        return summary.totalFunctions == scores.count
            && summary.measuredFunctions == measured
            && summary.assumedFunctions == assumed
            && summary.violations >= 0
            && summary.violations <= scores.count
            && summary.threshold.isFinite
            && summary.threshold >= 0
    }
}
