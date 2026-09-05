struct CLIArgumentParser {
    func parse(_ arguments: [String]) throws -> CLIAction {
        guard let command = arguments.first else {
            throw CLIError.missingOption("analyze")
        }
        if command == "--help" || command == "-h" || command == "help" {
            return .help
        }
        if command == "--version" || command == "version" {
            return .version
        }
        guard command == "analyze" else {
            throw CLIError.invalidOption(command)
        }
        if arguments.dropFirst().contains("--help") || arguments.dropFirst().contains("-h") {
            return .help
        }
        return try parseAnalyze(Array(arguments.dropFirst()))
    }

    private func parseAnalyze(_ arguments: [String]) throws -> CLIAction {
        var values = ParsedValues()
        var index = arguments.startIndex
        while index < arguments.endIndex {
            let option = arguments[index]
            index = arguments.index(after: index)
            let value = try value(after: option, in: arguments, index: &index)
            try values.append(option: option, value: value)
        }
        return try values.action()
    }

    private func value(after option: String, in arguments: [String], index: inout Int) throws -> String {
        guard index < arguments.endIndex else {
            throw CLIError.missingValue(option)
        }
        let value = arguments[index]
        guard !value.hasPrefix("--") else {
            throw CLIError.missingValue(option)
        }
        index = arguments.index(after: index)
        return value
    }
}
