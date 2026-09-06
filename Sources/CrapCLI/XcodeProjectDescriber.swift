import CrapApplication
import Foundation

struct XcodeProjectDescriber: XcodeProjectDescribing {
    func describe(_ selection: XcodeSelection) throws -> XcodeProjectMetadata {
        let capture = try CaptureFiles()
        defer { capture.remove() }
        let data = try output(
            selection,
            buildArguments: ["-derivedDataPath", capture.scratchURL.path],
            queryArguments: ["-showBuildSettingsForIndex", "-json"],
        )
        return try XcodeProjectMetadata(
            sourceFiles: sourceFiles(data, target: selection.target),
            compilerContexts: [],
        )
    }

    func describe(
        _ selection: XcodeSelection,
        matchingXcodebuildCommand command: [String],
        workingDirectory: String? = nil,
    ) throws -> XcodeProjectMetadata {
        let settings = try XcodeBuildSettingsReader().read(
            selection,
            matchingXcodebuildCommand: command,
            workingDirectory: workingDirectory,
        )
        let resultBundle = try XcodeBuildCommand().resultBundlePath(command, workingDirectory: workingDirectory)
        return try XcodeBuildLogReader().read(
            at: resultBundle,
            project: selection.project,
            settings: settings,
            target: selection.target,
        )
    }

    private func output(
        _ selection: XcodeSelection,
        buildArguments: [String],
        queryArguments: [String],
        workingDirectory: String? = nil,
    ) throws -> Data {
        let capture = try CaptureFiles()
        defer { capture.remove() }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
        process.arguments = xcodebuildArguments(
            selection,
            buildArguments: buildArguments,
            queryArguments: queryArguments,
        )
        process.currentDirectoryURL = workingDirectory.map { URL(fileURLWithPath: $0) }
        process.standardOutput = capture.output
        process.standardError = capture.error
        try process.run()
        process.waitUntilExit()
        capture.close()
        guard process.terminationStatus == 0 else {
            throw try SourceSelectionError.xcodeDescription(errorMessage(capture))
        }
        return try capture.outputData()
    }

    private func xcodebuildArguments(
        _ selection: XcodeSelection,
        buildArguments: [String],
        queryArguments: [String],
    ) -> [String] {
        [
            "xcodebuild",
            "-project", selection.project,
            "-scheme", selection.scheme,
            "-configuration", selection.configuration,
            "-destination", selection.destination,
            "-disableAutomaticPackageResolution",
        ] + buildArguments + queryArguments
    }

    private func errorMessage(_ capture: CaptureFiles) throws -> String {
        try String(decoding: capture.errorData(), as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func sourceFiles(_ data: Data, target: String) throws -> [String] {
        try swiftEntries(sourceDocument(data), target: target).keys.sorted()
    }

    private func sourceDocument(_ data: Data) throws -> [String: [String: XcodeSourceMetadata]] {
        let document: [String: [String: XcodeSourceMetadata]]
        do {
            document = try JSONDecoder().decode([String: [String: XcodeSourceMetadata]].self, from: data)
        } catch {
            throw SourceSelectionError.invalidXcodeMetadata("cannot decode index metadata: \(error)")
        }
        return document
    }

    private func swiftEntries(
        _ document: [String: [String: XcodeSourceMetadata]],
        target: String,
    ) throws -> [String: XcodeSourceMetadata] {
        guard let targetMetadata = document[target] else {
            throw SourceSelectionError.target(target)
        }
        let swiftEntries = targetMetadata.filter { $0.value.languageDialect == "Xcode.SourceCodeLanguage.Swift" }
        guard !swiftEntries.isEmpty else {
            throw SourceSelectionError.xcodeTargetHasNoSwiftSources(target)
        }
        return swiftEntries
    }
}
