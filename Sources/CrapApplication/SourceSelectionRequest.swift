public struct SourceSelectionRequest: Equatable, Sendable {
    public let scope: SourceScope
    public let rootOverride: String?
    public let exclusions: [String]

    public init(scope: SourceScope, rootOverride: String? = nil, exclusions: [String] = []) {
        self.scope = scope
        self.rootOverride = rootOverride
        self.exclusions = exclusions
    }
}
