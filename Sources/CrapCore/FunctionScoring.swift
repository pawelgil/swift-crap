import Foundation

struct FunctionScoring {
    func score(
        callable: Callable,
        measurement: CoverageMeasurement,
        status: String,
    ) -> FunctionScore {
        let coverage = measurement.executable == 0
            ? 0
            : Double(measurement.covered) / Double(measurement.executable)
        let complexity = Double(callable.complexity)
        let crap = complexity * complexity * pow(1 - coverage, 3) + complexity
        return FunctionScore(
            callable: callable,
            coveredLines: measurement.covered,
            executableLines: measurement.executable,
            coverage: coverage,
            crap: crap,
            coverageStatus: status,
        )
    }

    static func order(_ lhs: FunctionScore, _ rhs: FunctionScore) -> Bool {
        let left = lhs.callable
        let right = rhs.callable
        return (left.file, left.span.start, left.id) < (right.file, right.span.start, right.id)
    }
}
