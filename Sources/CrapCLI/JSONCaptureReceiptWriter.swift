import CrapApplication
import Foundation

struct JSONCaptureReceiptWriter: CaptureReceiptWriting {
    func write(_ receipt: CaptureReceipt, to path: String) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        try encoder.encode(receipt).write(to: URL(fileURLWithPath: path), options: .withoutOverwriting)
    }
}
