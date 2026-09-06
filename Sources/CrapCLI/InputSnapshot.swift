import CrapApplication
import Foundation

struct InputSnapshot: CaptureInputSnapshotting {
    func read(root: String, excluding paths: [String]) throws -> [String: String] {
        let base = URL(fileURLWithPath: root).standardizedFileURL.resolvingSymlinksInPath()
        let excluded = try Set(paths.flatMap { path in
            try [CanonicalPath().resolvePreservingLastComponent(path), CanonicalPath().resolve(path)]
        })
        var result: [String: String] = [:]
        var visited = Set<String>()
        try visit(base, relative: "", root: base, excluded: excluded, visited: &visited, result: &result)
        return result
    }

    private func visit(
        _ url: URL,
        relative: String,
        root: URL,
        excluded: Set<String>,
        visited: inout Set<String>,
        result: inout [String: String],
    ) throws {
        if !relative.isEmpty, [".git", ".build", "DerivedData", ".swift-crap"].contains(url.lastPathComponent) {
            return
        }
        let unresolved = try CanonicalPath().resolvePreservingLastComponent(url.path)
        guard !excluded.contains(unresolved) else { return }
        let resolved = url.resolvingSymlinksInPath()
        guard !excluded.contains(resolved.path) else { return }
        guard resolved.path == root.path || resolved.path.hasPrefix(root.path + "/") else {
            throw ProvenanceError.invalid("input symlink escapes root: \(url.path)")
        }
        let values = try resolved.resourceValues(forKeys: [.isDirectoryKey, .isRegularFileKey])
        if values.isDirectory == true {
            guard visited.insert(resolved.path).inserted else {
                throw ProvenanceError.invalid("input directory contains a symlink cycle: \(url.path)")
            }
            defer { visited.remove(resolved.path) }
            for child in try FileManager.default.contentsOfDirectory(at: resolved, includingPropertiesForKeys: nil)
                .sorted(by: { $0.path < $1.path })
            {
                let childPath = relative.isEmpty ? child.lastPathComponent : relative + "/" + child.lastPathComponent
                try visit(
                    child,
                    relative: childPath,
                    root: root,
                    excluded: excluded,
                    visited: &visited,
                    result: &result,
                )
            }
        } else if values.isRegularFile == true {
            result[relative] = try ContentDigest().file(at: resolved)
        } else {
            throw ProvenanceError.invalid("input is not a regular file: \(url.path)")
        }
    }
}
