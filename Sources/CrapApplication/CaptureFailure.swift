public enum CaptureFailure: Error, Equatable, CustomStringConvertible {
    case invalidRequest(String)
    case inputsChanged

    public var description: String {
        switch self {
        case let .invalidRequest(message): message
        case .inputsChanged: "project inputs changed during capture"
        }
    }
}
