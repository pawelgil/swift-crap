import Foundation

struct AnalysisPath {
    func root(_ path: String) throws -> String {
        guard !path.isEmpty else {
            throw AnalysisError.invalidRoot
        }
        return URL(fileURLWithPath: path).standardizedFileURL.resolvingSymlinksInPath().path
    }

    func canonical(_ path: String, root: String) -> String {
        if path.hasPrefix("/") {
            return URL(fileURLWithPath: path).standardizedFileURL.resolvingSymlinksInPath().path
        }
        return URL(fileURLWithPath: path, relativeTo: URL(fileURLWithPath: root, isDirectory: true))
            .standardizedFileURL.resolvingSymlinksInPath().path
    }

    func normalizedRelative(_ path: String) -> String? {
        var components: [Substring] = []
        for component in path.split(separator: "/") where component != "." {
            if component == ".." {
                guard !components.isEmpty else {
                    return nil
                }
                components.removeLast()
            } else {
                components.append(component)
            }
        }
        return components.isEmpty ? nil : components.joined(separator: "/")
    }
}
