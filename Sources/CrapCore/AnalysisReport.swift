public struct AnalysisReport: Codable, Equatable, Sendable {
    public let schemaVersion: Int
    public let metric: String
    public let functions: [FunctionScore]
    public let summary: ReportSummary

    public init(
        schemaVersion: Int = 1,
        metric: String = "crap-line-v1",
        functions: [FunctionScore],
        summary: ReportSummary,
    ) {
        self.schemaVersion = schemaVersion
        self.metric = metric
        self.functions = functions
        self.summary = summary
    }
}
