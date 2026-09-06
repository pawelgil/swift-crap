import Foundation

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

    func includes(file path: String) -> Bool {
        guard case .project = self else {
            return true
        }
        let name = URL(fileURLWithPath: path).lastPathComponent
        return name != "Package.swift" && !(name.hasPrefix("Package@swift-") && name.hasSuffix(".swift"))
    }
}
