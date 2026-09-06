import CrapApplication

struct LocalXcodeBuildProductResolver: XcodeBuildProductResolving {
    func product(
        selection: XcodeSelection,
        command: [String],
        workingDirectory: String,
    ) throws -> String {
        try XcodeBuildSettingsReader().read(
            selection,
            matchingXcodebuildCommand: command,
            workingDirectory: workingDirectory,
        ).buildProductPath
    }
}
