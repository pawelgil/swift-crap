import CrapApplication

protocol XcodeBuildProductResolving {
    func product(
        selection: XcodeSelection,
        command: [String],
        workingDirectory: String,
    ) throws -> String
}
