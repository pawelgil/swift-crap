import CrapApplication

struct CaptureArgumentParser {
    func parse(_ arguments: [String]) throws -> CLIAction {
        guard let separator = arguments.firstIndex(of: "--"), separator + 1 < arguments.count else {
            throw CLIError.missingOption("-- COMMAND")
        }
        var values: [String: String] = [:]
        var coverage: [String] = []
        var index = 0
        while index < separator {
            let option = arguments[index]
            guard index + 1 < separator else { throw CLIError.missingValue(option) }
            let value = arguments[index + 1]
            index += 2
            guard !value.hasPrefix("--") else { throw CLIError.missingValue(option) }
            if option == "--coverage" { coverage.append(value); continue }
            guard ["--root", "--output", "--build-description", "--build-context", "--xcode-project",
                   "--scheme", "--target", "--configuration", "--destination"].contains(option)
            else {
                throw CLIError.invalidOption(option)
            }
            guard values[option] == nil else { throw CLIError.invalidValue(option: option, value: "specified twice") }
            values[option] = value
        }
        guard let root = values["--root"], let output = values["--output"], !coverage.isEmpty else {
            throw CLIError.missingOption("--root, --output and --coverage")
        }
        guard values["--build-description"] == nil || values["--build-context"] == nil else {
            throw CLIError.selection("choose one compiler context source")
        }
        let xcode = try xcodeSelection(values)
        let contextCount = [values["--build-description"], values["--build-context"], values["--xcode-project"]]
            .compactMap(\.self).count
        guard contextCount == 1 else {
            throw CLIError.selection("choose exactly one of --build-description, --build-context or --xcode-project")
        }
        return .capture(CaptureRequest(
            root: root,
            output: output,
            coverage: coverage,
            buildDescription: values["--build-description"],
            buildContext: values["--build-context"],
            command: Array(arguments[(separator + 1)...]),
            xcode: xcode,
        ))
    }

    private func xcodeSelection(_ values: [String: String]) throws -> XcodeSelection? {
        guard let project = values["--xcode-project"] else {
            guard ["--scheme", "--target", "--configuration", "--destination"].allSatisfy({ values[$0] == nil }) else {
                throw CLIError.selection("Xcode options require --xcode-project")
            }
            return nil
        }
        guard let scheme = values["--scheme"], let target = values["--target"] else {
            throw CLIError.missingOption("--scheme and --target")
        }
        return XcodeSelection(
            project: project,
            scheme: scheme,
            target: target,
            configuration: values["--configuration"] ?? "Debug",
            destination: values["--destination"] ?? "platform=macOS",
        )
    }
}
