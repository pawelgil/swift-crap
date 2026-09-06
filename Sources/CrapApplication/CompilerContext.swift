public struct CompilerContext: Codable, Equatable, Sendable {
    public let compiler: String
    public let arguments: [String]
    public let directory: String
    public let sources: [String]
    public let moduleName: String

    public init(
        compiler: String,
        arguments: [String],
        directory: String,
        sources: [String],
        moduleName: String,
    ) {
        self.compiler = compiler
        self.arguments = arguments
        self.directory = directory
        self.sources = sources
        self.moduleName = moduleName
    }
}
