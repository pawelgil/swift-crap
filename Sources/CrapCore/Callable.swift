public struct Callable: Codable, Equatable, Sendable {
    public let id: String
    public let file: String
    public let name: String
    public let kind: CallableKind
    public let span: SourceSpan
    public let bodySpan: SourceSpan
    public let complexity: Int
    public let parentID: String?

    public init(
        id: String,
        file: String,
        name: String,
        kind: CallableKind,
        span: SourceSpan,
        bodySpan: SourceSpan,
        complexity: Int,
        parentID: String?,
    ) {
        self.id = id
        self.file = file
        self.name = name
        self.kind = kind
        self.span = span
        self.bodySpan = bodySpan
        self.complexity = complexity
        self.parentID = parentID
    }
}
