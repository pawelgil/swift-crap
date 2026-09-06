struct Exclusion {
    let components: [Substring]

    init(_ value: String) throws {
        guard !value.hasPrefix("/") else {
            throw SourceSelectionError.invalidExclusion(value)
        }
        let components = value.split(separator: "/", omittingEmptySubsequences: true)
        guard !components.isEmpty, !components.contains("."), !components.contains("..") else {
            throw SourceSelectionError.invalidExclusion(value)
        }
        self.components = components
    }

    func matches(_ path: String) -> Bool {
        let pathComponents = path.split(separator: "/", omittingEmptySubsequences: true)
        return pathComponents.starts(with: components)
    }
}
