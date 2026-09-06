enum XCCovExportError: Error, CustomStringConvertible, Equatable {
    case commandFailed(String)

    var description: String {
        switch self {
        case let .commandFailed(message): "xccov export failed: \(message)"
        }
    }
}
