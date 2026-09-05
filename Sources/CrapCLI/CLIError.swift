enum CLIError: Error, CustomStringConvertible, Equatable {
    case invalidOption(String)
    case invalidValue(option: String, value: String)
    case missingOption(String)
    case missingValue(String)
    case selection(String)

    var description: String {
        switch self {
        case let .invalidOption(option):
            "unknown option: \(option)"
        case let .invalidValue(option, value):
            "invalid value for \(option): \(value)"
        case let .missingOption(option):
            "missing required option: \(option)"
        case let .missingValue(option):
            "missing value for option: \(option)"
        case let .selection(message):
            message
        }
    }
}
