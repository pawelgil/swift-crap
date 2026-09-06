public struct CaptureRequest: Sendable {
    public let root: String
    public let output: String
    public let coverage: [String]
    public let buildDescription: String?
    public let buildContext: String?
    public let command: [String]
    public let xcode: XcodeSelection?

    public init(
        root: String,
        output: String,
        coverage: [String],
        buildDescription: String?,
        buildContext: String?,
        command: [String],
        xcode: XcodeSelection? = nil,
    ) {
        self.root = root
        self.output = output
        self.coverage = coverage
        self.buildDescription = buildDescription
        self.buildContext = buildContext
        self.command = command
        self.xcode = xcode
    }
}
