public struct SourcePosition: Codable, Equatable, Hashable, Sendable, Comparable {
    public let line: Int
    public let column: Int

    public init(line: Int, column: Int) {
        self.line = line
        self.column = column
    }

    public static func < (lhs: Self, rhs: Self) -> Bool {
        (lhs.line, lhs.column) < (rhs.line, rhs.column)
    }
}
