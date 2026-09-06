import CrapApplication
import Foundation

struct XcodeBuildCommand {
    func metadataArguments(
        _ command: [String],
        matching selection: XcodeSelection,
        workingDirectory: String? = nil,
    ) throws -> [String] {
        var arguments = try invocationArguments(command)
        try require(
            option: "-project",
            value: selection.project,
            in: arguments,
            path: true,
            workingDirectory: workingDirectory,
        )
        try require(option: "-scheme", value: selection.scheme, in: arguments)
        try require(option: "-configuration", value: selection.configuration, in: arguments)
        try require(option: "-destination", value: selection.destination, in: arguments)
        remove(options: ["-project", "-scheme", "-configuration", "-destination",
                         "-resultBundlePath", "-resultStreamPath", "-enableCodeCoverage"], from: &arguments)
        arguments.removeAll(where: ignoredFlag)
        return arguments
    }

    func resultBundlePath(_ command: [String], workingDirectory: String? = nil) throws -> String {
        let arguments = try invocationArguments(command)
        let paths = values(after: "-resultBundlePath", in: arguments)
        guard paths.count == 1, let path = paths.first, !path.isEmpty else {
            throw SourceSelectionError.xcodeCommand(
                "capture command must provide exactly one -resultBundlePath",
            )
        }
        return canonical(path, relativeTo: workingDirectory)
    }

    private func invocationArguments(_ command: [String]) throws -> [String] {
        guard let executable = command.first else {
            throw SourceSelectionError.xcodeCommand("missing xcodebuild command")
        }
        if URL(fileURLWithPath: executable).lastPathComponent == "xcodebuild" {
            return Array(command.dropFirst())
        }
        if URL(fileURLWithPath: executable).lastPathComponent == "xcrun", command.dropFirst().first == "xcodebuild" {
            return Array(command.dropFirst(2))
        }
        throw SourceSelectionError.xcodeCommand("capture command must invoke xcodebuild directly")
    }

    private func require(
        option: String,
        value: String,
        in arguments: [String],
        path: Bool = false,
        workingDirectory: String? = nil,
    ) throws {
        let actual = values(after: option, in: arguments)
        let matches = path
            ? actual.map { canonical($0, relativeTo: workingDirectory) } == [canonical(
                value,
                relativeTo: workingDirectory,
            )]
            : actual == [value]
        guard matches else {
            throw SourceSelectionError.xcodeCommand("\(option) must match \(value)")
        }
    }

    private func values(after option: String, in arguments: [String]) -> [String] {
        arguments.indices.compactMap { index in
            guard arguments[index] == option else {
                return nil
            }
            let valueIndex = arguments.index(after: index)
            return valueIndex < arguments.endIndex ? arguments[valueIndex] : nil
        }
    }

    private func remove(options: Set<String>, from arguments: inout [String]) {
        var retained: [String] = []
        var index = arguments.startIndex
        while index < arguments.endIndex {
            let argument = arguments[index]
            index = arguments.index(after: index)
            if options.contains(argument), index < arguments.endIndex {
                index = arguments.index(after: index)
            } else {
                retained.append(argument)
            }
        }
        arguments = retained
    }

    private func ignoredFlag(_ argument: String) -> Bool {
        ["analyze", "archive", "build", "build-for-testing", "clean", "test", "test-without-building",
         "-json", "-quiet", "-showBuildSettings", "-showBuildSettingsForIndex"].contains(argument)
            || argument.hasPrefix("-only-testing:")
            || argument.hasPrefix("-skip-testing:")
    }

    private func canonical(_ path: String, relativeTo directory: String?) -> String {
        let base = directory.map { URL(fileURLWithPath: $0, isDirectory: true) }
        return URL(fileURLWithPath: path, relativeTo: base).standardizedFileURL.resolvingSymlinksInPath().path
    }
}
