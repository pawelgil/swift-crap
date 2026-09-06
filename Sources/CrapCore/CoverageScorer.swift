struct CoverageScorer {
    private let functionScoring = FunctionScoring()

    func scores(
        _ callables: [Callable],
        observations: [String: [CoverageRecord]],
        missing: MissingCoveragePolicy,
    ) throws -> [FunctionScore] {
        try callables.map { callable in
            guard let records = observations[callable.id], !records.isEmpty else {
                return try missingScore(callable, policy: missing)
            }
            let measurement = try measurement(from: records, callableID: callable.id)
            return functionScoring.score(callable: callable, measurement: measurement, status: "measured")
        }
    }

    func summary(scores: [FunctionScore], violations: Int, threshold: Double) -> ReportSummary {
        ReportSummary(
            totalFunctions: scores.count,
            measuredFunctions: scores.count { $0.coverageStatus == "measured" },
            assumedFunctions: scores.count { $0.coverageStatus == "assumedZero" },
            violations: violations,
            threshold: threshold,
        )
    }

    private func missingScore(_ callable: Callable, policy: MissingCoveragePolicy) throws -> FunctionScore {
        guard policy == .zero else {
            throw AnalysisError.missingCoverage(callableID: callable.id)
        }
        return functionScoring.score(
            callable: callable,
            measurement: CoverageMeasurement(covered: 0, executable: 0),
            status: "assumedZero",
        )
    }

    private func measurement(from records: [CoverageRecord], callableID: String) throws -> CoverageMeasurement {
        let lineRecords = records.compactMap(\.lines)
        if !lineRecords.isEmpty {
            guard lineRecords.count == records.count else {
                throw AnalysisError.mixedCoverageRepresentations(callableID: callableID)
            }
            return try lineMeasurement(lineRecords, callableID: callableID)
        }
        return try aggregateMeasurement(records, callableID: callableID)
    }

    private func lineMeasurement(_ observations: [[CoverageLine]], callableID: String) throws -> CoverageMeasurement {
        let universe = Set(observations[0].map(\.line))
        guard observations.dropFirst().allSatisfy({ Set($0.map(\.line)) == universe }) else {
            throw AnalysisError.inconsistentLineUniverse(callableID: callableID)
        }
        let covered = observations.reduce(into: Set<Int>()) { result, lines in
            result.formUnion(lines.lazy.filter(\.covered).map(\.line))
        }
        return CoverageMeasurement(covered: covered.count, executable: universe.count)
    }

    private func aggregateMeasurement(_ records: [CoverageRecord], callableID: String) throws -> CoverageMeasurement {
        guard let first = records.first,
              records.dropFirst().allSatisfy({ $0 == first }),
              let covered = first.coveredLines,
              let executable = first.executableLines
        else {
            throw AnalysisError.ambiguousAggregateCoverage(callableID: callableID)
        }
        return CoverageMeasurement(covered: covered, executable: executable)
    }
}
