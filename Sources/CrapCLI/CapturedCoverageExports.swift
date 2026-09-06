import Foundation

struct CapturedCoverageExports {
    let values: [String: Data]

    init(_ exports: [String: Data]) throws {
        guard exports.values.allSatisfy({ !$0.isEmpty }) else {
            throw ProvenanceError.invalid("capture contains empty coverage export")
        }
        let pairs = try exports.map { try (CanonicalPath().resolve($0.key), $0.value) }
        guard Set(pairs.map(\.0)).count == pairs.count else {
            throw ProvenanceError.invalid("capture contains duplicate coverage export paths")
        }
        values = Dictionary(uniqueKeysWithValues: pairs)
    }
}
