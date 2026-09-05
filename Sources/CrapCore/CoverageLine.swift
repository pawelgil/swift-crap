public struct CoverageLine: Codable, Equatable, Sendable {
    public let line: Int
    public let covered: Bool

    public init(line: Int, covered: Bool) {
        self.line = line
        self.covered = covered
    }
}
