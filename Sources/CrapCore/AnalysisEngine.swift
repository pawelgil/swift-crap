public struct AnalysisEngine: Sendable {
    public init() {}

    public func analyze(
        callables: [Callable],
        coverage: [CoverageRecord],
        root: String,
        missing: MissingCoveragePolicy,
        threshold: Double,
        baseline: AnalysisReport? = nil,
    ) throws -> AnalysisReport {
        let validator = AnalysisInputValidator()
        try validator.validate(threshold: threshold)
        let canonicalRoot = try validator.validate(root: root)
        try validator.validate(callables: callables)
        try validator.validate(coverage: coverage)
        let baselineEvaluator = BaselineEvaluator()
        let baselineScores = try baselineEvaluator.validatedScores(from: baseline)
        let observations = try CoverageReconciler(root: canonicalRoot).reconcile(coverage, with: callables)
        let scorer = CoverageScorer()
        let scores = try scorer.scores(callables, observations: observations, missing: missing)
            .sorted(by: FunctionScoring.order)
        let violations = baselineEvaluator.violationCount(
            scores: scores,
            threshold: threshold,
            baseline: baselineScores,
        )
        return AnalysisReport(
            functions: scores,
            summary: scorer.summary(scores: scores, violations: violations, threshold: threshold),
        )
    }
}
