import CrapApplication
import Foundation

struct LocalCaptureCoverageExporter: CaptureCoverageExporting {
    private let exporter: any XcodeNativeCoverageExporting

    init(exporter: any XcodeNativeCoverageExporting = XcodeNativeCoverageExporter()) {
        self.exporter = exporter
    }

    func read(request: CaptureRequest, paths: CapturePaths, contexts: [CompilerContext]) throws -> [String: Data] {
        guard let selection = request.xcode else { return [:] }
        let result = try XcodeBuildCommand().resultBundlePath(request.command, workingDirectory: paths.root)
        guard paths.coverage.contains(result) else {
            throw ProvenanceError.invalid("Xcode result bundle must be a declared coverage artifact")
        }
        let data = try exporter.export(
            resultBundle: result,
            selection: selection,
            contexts: contexts,
            command: request.command,
            root: paths.root,
        )
        return [result: data]
    }
}
