public struct CoverageRecord: Codable, Equatable, Sendable {
    public let file: String
    public let name: String
    public let span: SourceSpan?
    public let anchor: SourcePosition
    public let lines: [CoverageLine]?
    public let coveredLines: Int?
    public let executableLines: Int?

    public init(
        file: String,
        name: String,
        span: SourceSpan?,
        anchor: SourcePosition,
        lines: [CoverageLine]?,
        coveredLines: Int?,
        executableLines: Int?,
    ) {
        self.file = file
        self.name = name
        self.span = span
        self.anchor = anchor
        self.lines = lines
        self.coveredLines = coveredLines
        self.executableLines = executableLines
    }
}
