public struct ReportSummary: Codable, Equatable, Sendable {
    public let totalFunctions: Int
    public let measuredFunctions: Int
    public let assumedFunctions: Int
    public let violations: Int
    public let threshold: Double

    public init(
        totalFunctions: Int,
        measuredFunctions: Int,
        assumedFunctions: Int,
        violations: Int,
        threshold: Double,
    ) {
        self.totalFunctions = totalFunctions
        self.measuredFunctions = measuredFunctions
        self.assumedFunctions = assumedFunctions
        self.violations = violations
        self.threshold = threshold
    }
}
