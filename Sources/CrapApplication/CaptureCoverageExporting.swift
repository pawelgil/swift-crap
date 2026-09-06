import Foundation

public protocol CaptureCoverageExporting {
    func read(request: CaptureRequest, paths: CapturePaths, contexts: [CompilerContext]) throws -> [String: Data]
}
