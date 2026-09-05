public struct SelectedSources: Equatable, Sendable {
    public let root: String
    public let files: [SelectedSource]

    public init(root: String, files: [SelectedSource]) {
        self.root = root
        self.files = files
    }
}
