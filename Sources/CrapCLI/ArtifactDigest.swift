import CrapApplication
import Foundation

struct ArtifactDigest: CaptureArtifactDigesting {
    func read(at path: String) throws -> String {
        let url = URL(fileURLWithPath: path).standardizedFileURL
        let values = try url.resourceValues(forKeys: [.isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey])
        guard values.isSymbolicLink != true else { throw ProvenanceError.invalid("artifact is a symlink: \(path)") }
        if values.isRegularFile == true { return try ContentDigest().file(at: url) }
        guard values.isDirectory == true else { throw ProvenanceError.invalid("invalid artifact: \(path)") }
        var entries: [String: String] = [:]
        for child in try FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: nil) {
            entries[child.lastPathComponent] = try read(at: child.path)
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try ContentDigest().hash(encoder.encode(entries))
    }
}
