enum Filtering {
    case explicit
    case project

    func includes(directory path: String) -> Bool {
        guard case .project = self else {
            return true
        }
        let excluded = Set([
            ".build",
            ".git",
            ".swiftpm",
            "DerivedData",
            "Fixtures",
            "Packages",
            "TestFixtures",
            "Tests",
        ])
        return !path.split(separator: "/").contains { component in
            component.hasPrefix(".") || excluded.contains(String(component))
        }
    }
}
