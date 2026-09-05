public struct SourceSpan: Codable, Equatable, Hashable, Sendable {
    public let start: SourcePosition
    public let end: SourcePosition

    public init(start: SourcePosition, end: SourcePosition) {
        self.start = start
        self.end = end
    }

    public func contains(_ position: SourcePosition) -> Bool {
        start <= position && position < end
    }
}
