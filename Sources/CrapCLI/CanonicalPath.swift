import Foundation

struct CanonicalPath {
    func resolve(_ path: String, relativeTo directory: String? = nil) throws -> String {
        let base = directory.map { URL(fileURLWithPath: $0, isDirectory: true) }
        let original = URL(fileURLWithPath: path, relativeTo: base).standardizedFileURL
        var existing = original
        var missing: [String] = []
        while !FileManager.default.fileExists(atPath: existing.path) {
            guard existing.path != "/" else {
                throw ProvenanceError.invalid("path has no existing ancestor: \(path)")
            }
            missing.insert(existing.lastPathComponent, at: 0)
            existing.deleteLastPathComponent()
        }
        return missing.reduce(existing.resolvingSymlinksInPath()) { result, component in
            result.appendingPathComponent(component)
        }.standardizedFileURL.path
    }

    func resolvePreservingLastComponent(_ path: String, relativeTo directory: String? = nil) throws -> String {
        let base = directory.map { URL(fileURLWithPath: $0, isDirectory: true) }
        let original = URL(fileURLWithPath: path, relativeTo: base).standardizedFileURL
        let parent = try resolve(original.deletingLastPathComponent().path)
        return URL(fileURLWithPath: parent, isDirectory: true).appendingPathComponent(original.lastPathComponent).path
    }
}
