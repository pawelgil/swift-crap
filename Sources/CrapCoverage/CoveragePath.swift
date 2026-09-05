import Foundation

enum CoveragePath {
    static func normalize(_ path: String) -> String {
        if path.hasPrefix("/") {
            return URL(fileURLWithPath: path).standardizedFileURL.resolvingSymlinksInPath().path
        }
        var components: [Substring] = []
        for component in path.split(separator: "/") where component != "." {
            if component == "..", components.last != nil, components.last != ".." {
                components.removeLast()
            } else {
                components.append(component)
            }
        }
        return components.isEmpty ? "." : components.joined(separator: "/")
    }
}
