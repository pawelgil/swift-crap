enum XcodeNativeCoverageExportError: Error, CustomStringConvertible, Equatable {
    case invalidEvidence(String)
    case commandFailed(String)
    case candidateFailures([String])
    case conflictingCandidates([String])

    var description: String {
        switch self {
        case let .invalidEvidence(reason):
            "invalid Xcode coverage evidence: \(reason)"
        case let .commandFailed(reason):
            "native Xcode coverage export failed: \(reason)"
        case let .candidateFailures(failures):
            "native Xcode coverage candidates failed: \(failures.joined(separator: "; "))"
        case let .conflictingCandidates(paths):
            "native Xcode coverage candidates produced different exports: \(paths.joined(separator: ", "))"
        }
    }
}
