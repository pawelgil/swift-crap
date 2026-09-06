import CrapApplication
import Foundation

struct XcodeBuildSettingsReader {
    func read(
        _ selection: XcodeSelection,
        matchingXcodebuildCommand command: [String],
        workingDirectory: String? = nil,
    ) throws -> XcodeResolvedBuildSettings {
        let buildArguments = try XcodeBuildCommand().metadataArguments(
            command,
            matching: selection,
            workingDirectory: workingDirectory,
        )
        let data = try output(selection, buildArguments: buildArguments, workingDirectory: workingDirectory)
        let settings = try decode(data, target: selection.target)
        try validateArchitecture(settings, target: selection.target)
        return try XcodeResolvedBuildSettings(
            settings,
            selection: selection,
            workingDirectory: workingDirectory,
        )
    }

    private func output(
        _ selection: XcodeSelection,
        buildArguments: [String],
        workingDirectory: String?,
    ) throws -> Data {
        let capture = try CaptureFiles()
        defer { capture.remove() }
        let process = process(
            selection,
            buildArguments: buildArguments,
            workingDirectory: workingDirectory,
            capture: capture,
        )
        try execute(process, capture: capture)
        return try capture.outputData()
    }

    private func process(
        _ selection: XcodeSelection,
        buildArguments: [String],
        workingDirectory: String?,
        capture: CaptureFiles,
    ) -> Process {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
        process.arguments = arguments(selection, buildArguments: buildArguments)
        process.currentDirectoryURL = workingDirectory.map { URL(fileURLWithPath: $0) }
        process.standardOutput = capture.output
        process.standardError = capture.error
        return process
    }

    private func execute(_ process: Process, capture: CaptureFiles) throws {
        try process.run()
        process.waitUntilExit()
        capture.close()
        guard process.terminationStatus == 0 else {
            throw try SourceSelectionError.xcodeDescription(errorMessage(capture))
        }
    }

    private func arguments(_ selection: XcodeSelection, buildArguments: [String]) -> [String] {
        [
            "xcodebuild",
            "-project", selection.project,
            "-scheme", selection.scheme,
            "-configuration", selection.configuration,
            "-destination", selection.destination,
            "-disableAutomaticPackageResolution",
        ] + buildArguments + ["-showBuildSettings", "-json"]
    }

    private func decode(_ data: Data, target: String) throws -> [String: String] {
        let entries: [XcodeBuildSettingsMetadata]
        do {
            entries = try JSONDecoder().decode([XcodeBuildSettingsMetadata].self, from: data)
        } catch {
            throw SourceSelectionError.invalidXcodeMetadata("cannot decode build settings: \(error)")
        }
        let matches = entries.filter { $0.target == target }
        guard matches.count == 1, let settings = matches.first?.buildSettings else {
            throw SourceSelectionError.target(target)
        }
        return settings
    }

    private func validateArchitecture(_ settings: [String: String], target: String) throws {
        let architectures = words(settings["ARCHS"]).subtracting(words(settings["EXCLUDED_ARCHS"]))
        guard !architectures.isEmpty else {
            throw SourceSelectionError.invalidXcodeMetadata("target \(target) has no effective architecture")
        }
        guard settings["ONLY_ACTIVE_ARCH"] == "YES" || architectures.count <= 1 else {
            let names = architectures.sorted().joined(separator: ", ")
            throw SourceSelectionError.xcodeCommand(
                "capture builds multiple architectures (\(names)); set ARCHS to one architecture or ONLY_ACTIVE_ARCH=YES",
            )
        }
    }

    private func words(_ value: String?) -> Set<String> {
        Set(value?.split(whereSeparator: \.isWhitespace).map(String.init) ?? [])
    }

    private func errorMessage(_ capture: CaptureFiles) throws -> String {
        try String(decoding: capture.errorData(), as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
