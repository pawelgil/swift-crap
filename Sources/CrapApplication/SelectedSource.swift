public struct SelectedSource: Equatable, Sendable {
    public let path: String
    public let relativePath: String

    public init(path: String, relativePath: String) {
        self.path = path
        self.relativePath = relativePath
    }
}
