public enum AnalysisError: Error, Equatable, Sendable, CustomStringConvertible {
    case ambiguousAggregateCoverage(callableID: String)
    case ambiguousCoverage(recordName: String, file: String)
    case duplicateBaselineID(String)
    case duplicateCallableID(String)
    case emptyCallableInventory
    case incompatibleBaseline
    case inconsistentLineUniverse(callableID: String)
    case invalidCallable(String)
    case invalidCoverage(recordName: String, file: String)
    case invalidRoot
    case invalidThreshold
    case missingCoverage(callableID: String)
    case mixedCoverageRepresentations(callableID: String)

    public var description: String {
        switch self {
        case let .ambiguousAggregateCoverage(id):
            "Aggregate coverage observations for \(id) cannot be combined without owned lines."
        case let .ambiguousCoverage(name, file):
            "Coverage record \(name) in \(file) matches multiple source callables."
        case let .duplicateBaselineID(id):
            "Baseline contains duplicate callable ID \(id)."
        case let .duplicateCallableID(id):
            "Source analysis contains duplicate callable ID \(id)."
        case .emptyCallableInventory:
            "Source analysis produced no callables."
        case .incompatibleBaseline:
            "Baseline schema, metric, summary, or function scores are incompatible."
        case let .inconsistentLineUniverse(id):
            "Coverage observations for \(id) have inconsistent executable line sets."
        case let .invalidCallable(id):
            "Source callable \(id) has invalid identity, path, span, or complexity."
        case let .invalidCoverage(name, file):
            "Coverage record \(name) in \(file) has invalid positions, lines, or counts."
        case .invalidRoot:
            "Analysis root must be a nonempty path."
        case .invalidThreshold:
            "CRAP threshold must be finite and nonnegative."
        case let .missingCoverage(id):
            "Missing coverage for source callable \(id)."
        case let .mixedCoverageRepresentations(id):
            "Coverage observations for \(id) mix line and aggregate representations."
        }
    }
}
