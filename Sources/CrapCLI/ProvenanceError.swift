enum ProvenanceError: Error, Equatable, CustomStringConvertible {
    case invalid(String)

    var description: String {
        switch self {
        case let .invalid(reason): "invalid provenance: \(reason)"
        }
    }
}
