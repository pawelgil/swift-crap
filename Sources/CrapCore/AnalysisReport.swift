public struct AnalysisReport: Codable, Equatable, Sendable {
    public let schemaVersion: Int
    public let metric: String
    public let functions: [FunctionScore]
    public let summary: ReportSummary
    public let verification: String?
    public let buildIdentity: String?

    public init(
        schemaVersion: Int = 1,
        metric: String = "crap-line-v1",
        functions: [FunctionScore],
        summary: ReportSummary,
        verification: String? = nil,
        buildIdentity: String? = nil,
    ) {
        self.schemaVersion = schemaVersion
        self.metric = metric
        self.functions = functions
        self.summary = summary
        self.verification = verification
        self.buildIdentity = buildIdentity
    }
}
