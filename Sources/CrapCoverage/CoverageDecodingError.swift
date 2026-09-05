public enum CoverageDecodingError: Error, Equatable, Sendable, CustomStringConvertible {
    case invalidCounts
    case malformedInput
    case oversizedLineRange(maximumExpandedLines: Int)
    case unsupportedSchema
    case unsupportedLLVMVersion(String)

    public var description: String {
        switch self {
        case .invalidCounts:
            "Coverage counts or line coverage fraction are inconsistent."
        case .malformedInput:
            "Coverage JSON is malformed or missing required fields."
        case let .oversizedLineRange(maximumExpandedLines):
            "LLVM function coverage spans more than the supported maximum of \(maximumExpandedLines) lines."
        case .unsupportedSchema:
            "Unsupported coverage schema; expected LLVM coverage JSON 2.x or 3.x, or xccov JSON."
        case let .unsupportedLLVMVersion(version):
            "Unsupported LLVM coverage JSON version \(version); supported major versions are 2 and 3."
        }
    }
}
