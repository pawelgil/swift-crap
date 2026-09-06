import CrapCore

public struct AnalysisRequest: Sendable {
    public let selection: SourceSelectionRequest
    public let coverageFiles: [String]
    public let missing: MissingCoveragePolicy
    public let threshold: Double
    public let baselineFile: String?
    public let provenanceFile: String?
    public let trustUnverifiedCoverage: Bool

    public init(
        selection: SourceSelectionRequest,
        coverageFiles: [String],
        missing: MissingCoveragePolicy = .error,
        threshold: Double = 30,
        baselineFile: String? = nil,
        provenanceFile: String? = nil,
        trustUnverifiedCoverage: Bool = false,
    ) {
        self.selection = selection
        self.coverageFiles = coverageFiles
        self.missing = missing
        self.threshold = threshold
        self.baselineFile = baselineFile
        self.provenanceFile = provenanceFile
        self.trustUnverifiedCoverage = trustUnverifiedCoverage
    }
}
