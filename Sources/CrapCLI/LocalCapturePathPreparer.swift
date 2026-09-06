import CrapApplication
import Foundation

struct LocalCapturePathPreparer: CapturePathPreparing {
    func prepare(_ request: CaptureRequest) throws -> CapturePaths {
        let root = try CanonicalPath().resolve(request.root)
        let output = try CanonicalPath().resolve(request.output)
        let coverage = try request.coverage.map { try CanonicalPath().resolve($0) }
        let outputs = [output] + coverage
        guard Set(outputs).count == outputs.count, root != "/" else {
            throw ProvenanceError.invalid("invalid capture paths")
        }
        guard !outputs.contains(where: { candidate in
            outputs.contains(where: { other in candidate != other && candidate.hasPrefix(other + "/") })
        }) else {
            throw ProvenanceError.invalid("capture outputs overlap")
        }
        for path in outputs {
            guard !FileManager.default.fileExists(atPath: path) else {
                throw ProvenanceError.invalid("capture output already exists: \(path); use a fresh path")
            }
            guard path != root, !root.hasPrefix(path + "/") else {
                throw ProvenanceError.invalid("output contains root")
            }
        }
        return try CapturePaths(root: root, output: output, coverage: coverage, xcode: xcode(request.xcode, root: root))
    }

    private func xcode(_ selection: XcodeSelection?, root: String) throws -> XcodeSelection? {
        guard let selection else { return nil }
        return try XcodeSelection(
            project: CanonicalPath().resolve(selection.project, relativeTo: root),
            scheme: selection.scheme,
            target: selection.target,
            configuration: selection.configuration,
            destination: selection.destination,
        )
    }
}
