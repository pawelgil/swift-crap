import CrapApplication
import Foundation

protocol XcodeNativeCoverageExporting {
    func export(
        resultBundle: String,
        selection: XcodeSelection,
        contexts: [CompilerContext],
        command: [String],
        root: String,
    ) throws -> Data
}
