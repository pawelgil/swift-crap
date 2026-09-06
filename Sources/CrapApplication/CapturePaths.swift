public struct CapturePaths: Equatable, Sendable {
    public let root: String
    public let output: String
    public let coverage: [String]
    public let xcode: XcodeSelection?

    public init(root: String, output: String, coverage: [String], xcode: XcodeSelection? = nil) {
        self.root = root
        self.output = output
        self.coverage = coverage
        self.xcode = xcode
    }
}
