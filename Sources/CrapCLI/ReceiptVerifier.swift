import CrapApplication
import Foundation

struct ReceiptVerifier {
    func read(at path: String, coverage: [String]) throws -> CaptureReceipt {
        let receipt = try JSONDecoder().decode(CaptureReceipt.self, from: Data(contentsOf: URL(fileURLWithPath: path)))
        guard receipt.schemaVersion == 1, receipt.metric == "crap-line-v1", !receipt.command.isEmpty,
              !receipt.contexts.isEmpty, !receipt.inputs.isEmpty, !receipt.artifacts.isEmpty
        else {
            throw ProvenanceError.invalid("unsupported or incomplete receipt")
        }
        try validate(receipt, at: path, coverage: coverage)
        return receipt
    }

    func validate(_ receipt: CaptureReceipt, at path: String, coverage: [String]) throws {
        let root = try CanonicalPath().resolve(receipt.root)
        guard root != "/" else { throw ProvenanceError.invalid("invalid capture root") }
        let receiptPath = try CanonicalPath().resolve(path)
        let storedArtifacts = try canonicalArtifacts(receipt.artifacts)
        let current = try InputSnapshot().read(root: root, excluding: [receiptPath] + Array(storedArtifacts.keys))
        guard current == receipt.inputs
        else { throw ProvenanceError.invalid("project inputs differ from captured sources") }
        for artifact in coverage {
            let canonical = try CanonicalPath().resolve(artifact)
            guard let expected = storedArtifacts[canonical], try ArtifactDigest().read(at: canonical) == expected else {
                throw ProvenanceError.invalid("coverage artifact is not captured or has changed: \(artifact)")
            }
        }
    }

    private func canonicalArtifacts(_ artifacts: [String: String]) throws -> [String: String] {
        let pairs = try artifacts.map { try (CanonicalPath().resolve($0.key), $0.value) }
        guard Set(pairs.map(\.0)).count == pairs.count else {
            throw ProvenanceError.invalid("capture contains duplicate artifact paths")
        }
        return Dictionary(uniqueKeysWithValues: pairs)
    }
}
