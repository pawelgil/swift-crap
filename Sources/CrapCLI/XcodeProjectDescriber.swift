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
        let buildArguments = try XcodeBuildCommand().metadataArguments(
            command,
            matching: selection,
            workingDirectory: workingDirectory,
        )
        try requireSingleArchitecture(
            selection,
            buildArguments: buildArguments,
            workingDirectory: workingDirectory,
        )
        return try describe(
            selection,
            buildArguments: buildArguments,
            workingDirectory: workingDirectory,
        )
    }

    private func describe(
        _ selection: XcodeSelection,
        buildArguments: [String],
        workingDirectory: String? = nil,
    ) throws -> XcodeProjectMetadata {
        let data = try output(
            selection,
            buildArguments: buildArguments,
            queryArguments: ["-showBuildSettingsForIndex", "-json"],
            workingDirectory: workingDirectory,
        )
        return try decode(data, target: selection.target)
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

    private func requireSingleArchitecture(
        _ selection: XcodeSelection,
        buildArguments: [String],
        workingDirectory: String?,
    ) throws {
        let data = try output(
            selection,
            buildArguments: buildArguments,
            queryArguments: ["-showBuildSettings", "-json"],
            workingDirectory: workingDirectory,
        )
        let entries: [XcodeBuildSettingsMetadata]
        do {
            entries = try JSONDecoder().decode([XcodeBuildSettingsMetadata].self, from: data)
        } catch {
            throw SourceSelectionError.invalidXcodeMetadata("cannot decode build settings: \(error)")
        }
        let matches = entries.filter { $0.target == selection.target }
        guard matches.count == 1, let settings = matches.first?.buildSettings else {
            throw SourceSelectionError.target(selection.target)
        }
        let architectures = builtArchitectures(settings, destination: selection.destination)
        guard !architectures.isEmpty else {
            throw SourceSelectionError.invalidXcodeMetadata("target \(selection.target) has no effective architecture")
        }
        guard settings["ONLY_ACTIVE_ARCH"] == "YES" || architectures.count <= 1 else {
            let names = architectures.sorted().joined(separator: ", ")
            throw SourceSelectionError.xcodeCommand(
                "capture builds multiple architectures (\(names)); select one destination architecture",
            )
        }
    }

    private func builtArchitectures(_ settings: [String: String], destination: String) -> Set<String> {
        if let architecture = destinationArchitecture(destination) {
            return [architecture]
        }
        let architectures = words(settings["ARCHS"])
        let excluded = words(settings["EXCLUDED_ARCHS"])
        return Set(architectures).subtracting(excluded)
    }

    private func destinationArchitecture(_ destination: String) -> String? {
        destination.split(separator: ",").compactMap { component in
            let values = component.split(separator: "=", maxSplits: 1).map {
                $0.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            return values.count == 2 && values[0].lowercased() == "arch" ? values[1] : nil
        }.first
    }

    private func words(_ value: String?) -> Set<String> {
        Set(value?.split(whereSeparator: \.isWhitespace).map(String.init) ?? [])
    }

    private func errorMessage(_ capture: CaptureFiles) throws -> String {
        try String(decoding: capture.errorData(), as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func decode(_ data: Data, target: String) throws -> XcodeProjectMetadata {
        let document = try sourceDocument(data)
        let swiftEntries = try swiftEntries(document, target: target)
        let sourceFiles = swiftEntries.keys.sorted()
        let contexts = try compilerContexts(entries: swiftEntries, sourceFiles: sourceFiles)
        return XcodeProjectMetadata(sourceFiles: sourceFiles, compilerContexts: contexts)
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

    private func compilerContexts(
        entries: [String: XcodeSourceMetadata],
        sourceFiles: [String],
    ) throws -> [CompilerContext] {
        var contexts: [CompilerContext] = []
        var compilers: [String: String] = [:]
        let sourceSet = Set(sourceFiles)
        for source in sourceFiles {
            guard let metadata = entries[source] else {
                throw SourceSelectionError.invalidXcodeMetadata("missing entry for source \(source)")
            }
            guard let arguments = metadata.swiftASTCommandArguments, !arguments.isEmpty else {
                throw SourceSelectionError.invalidXcodeMetadata("source \(source) has no Swift compiler arguments")
            }
            guard let moduleName = metadata.swiftASTModuleName, !moduleName.isEmpty else {
                throw SourceSelectionError.invalidXcodeMetadata("source \(source) has no Swift module name")
            }
            guard let toolchains = metadata.toolchains, !toolchains.isEmpty else {
                throw SourceSelectionError.invalidXcodeMetadata("source \(source) has no toolchain")
            }
            guard toolchains.count == 1, let toolchain = toolchains.first else {
                throw SourceSelectionError.invalidXcodeMetadata(
                    "source \(source) has ambiguous toolchains: \(toolchains.joined(separator: ", "))",
                )
            }
            guard let directory = value(after: "-working-directory", in: arguments) else {
                throw SourceSelectionError.invalidXcodeMetadata("source \(source) has no working directory")
            }
            let compilerPath: String
            if let resolved = compilers[toolchain] {
                compilerPath = resolved
            } else {
                compilerPath = try compiler(toolchain: toolchain)
                compilers[toolchain] = compilerPath
            }
            let context = CompilerContext(
                compiler: compilerPath,
                arguments: arguments,
                directory: directory,
                sources: arguments.filter(sourceSet.contains),
                moduleName: moduleName,
            )
            guard Set(context.sources) == sourceSet else {
                throw SourceSelectionError.invalidXcodeMetadata("source \(source) has an incomplete Swift source list")
            }
            if !contexts.contains(context) {
                contexts.append(context)
            }
        }
        return contexts
    }

    private func value(after option: String, in arguments: [String]) -> String? {
        guard let index = arguments.lastIndex(of: option) else {
            return nil
        }
        let valueIndex = arguments.index(after: index)
        return valueIndex < arguments.endIndex ? arguments[valueIndex] : nil
    }

    private func compiler(toolchain: String) throws -> String {
        let capture = try CaptureFiles()
        defer { capture.remove() }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
        process.arguments = ["--toolchain", toolchain, "--find", "swiftc"]
        process.standardOutput = capture.output
        process.standardError = capture.error
        try process.run()
        process.waitUntilExit()
        capture.close()
        guard process.terminationStatus == 0 else {
            throw try SourceSelectionError.xcodeDescription(errorMessage(capture))
        }
        let path = try String(decoding: capture.outputData(), as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !path.isEmpty else {
            throw SourceSelectionError.invalidXcodeMetadata("xcrun returned an empty Swift compiler path")
        }
        return path
    }
}
