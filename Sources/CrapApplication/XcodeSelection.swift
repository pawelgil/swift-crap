public struct XcodeSelection: Codable, Equatable, Sendable {
    public let project: String
    public let scheme: String
    public let target: String
    public let configuration: String
    public let destination: String

    public init(
        project: String,
        scheme: String,
        target: String,
        configuration: String = "Debug",
        destination: String = "platform=macOS",
    ) {
        self.project = project
        self.scheme = scheme
        self.target = target
        self.configuration = configuration
        self.destination = destination
    }
}
