public struct FunctionScore: Codable, Equatable, Sendable {
    public let callable: Callable
    public let coveredLines: Int
    public let executableLines: Int
    public let coverage: Double
    public let crap: Double
    public let coverageStatus: String

    public init(
        callable: Callable,
        coveredLines: Int,
        executableLines: Int,
        coverage: Double,
        crap: Double,
        coverageStatus: String,
    ) {
        self.callable = callable
        self.coveredLines = coveredLines
        self.executableLines = executableLines
        self.coverage = coverage
        self.crap = crap
        self.coverageStatus = coverageStatus
    }
}
