import CrapApplication
import CrapCore
import Foundation

struct CapturedSourceAnalyzer: SourceAnalyzing {
    let receipt: CaptureReceipt

    func analyze(source: String, file: String) throws -> [Callable] {
        guard receipt.inputs[file] != nil,
              receipt.contexts.contains(where: { context in
                  context.sources
                      .contains {
                          URL(fileURLWithPath: $0).standardizedFileURL.resolvingSymlinksInPath().path == receipt
                              .root + "/" + file
                      }
              })
        else {
            throw ProvenanceError.invalid("source has no captured compiler context: \(file)")
        }
        return receipt.callables.filter { $0.file == file }
    }
}
