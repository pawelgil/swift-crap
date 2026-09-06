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
        let settings = try buildSettings(
            selection,
            buildArguments: buildArguments,
            workingDirectory: workingDirectory,
        )
        return try describe(
            selection,
            buildArguments: buildArguments,
            compiler: compiler(buildSettings: settings),
            workingDirectory: workingDirectory,
        )
    }

    private func describe(
        _ selection: XcodeSelection,
        buildArguments: [String],
        compiler: String,
        workingDirectory: String? = nil,
    ) throws -> XcodeProjectMetadata {
        let data = try output(
            selection,
            buildArguments: buildArguments,
            queryArguments: ["-showBuildSettingsForIndex", "-json"],
            workingDirectory: workingDirectory,
        )
        return try decode(data, target: selection.target, compiler: compiler)
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

    private func buildSettings(
        _ selection: XcodeSelection,
        buildArguments: [String],
        workingDirectory: String?,
    ) throws -> [String: String] {
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
        let architectures = builtArchitectures(settings)
        guard !architectures.isEmpty else {
            throw SourceSelectionError.invalidXcodeMetadata("target \(selection.target) has no effective architecture")
        }
        guard settings["ONLY_ACTIVE_ARCH"] == "YES" || architectures.count <= 1 else {
            let names = architectures.sorted().joined(separator: ", ")
            throw SourceSelectionError.xcodeCommand(
                "capture builds multiple architectures (\(names)); set ARCHS to one architecture or ONLY_ACTIVE_ARCH=YES",
            )
        }
        return settings
    }

    private func builtArchitectures(_ settings: [String: String]) -> Set<String> {
        let architectures = words(settings["ARCHS"])
        let excluded = words(settings["EXCLUDED_ARCHS"])
        return Set(architectures).subtracting(excluded)
    }

    private func words(_ value: String?) -> Set<String> {
        Set(value?.split(whereSeparator: \.isWhitespace).map(String.init) ?? [])
    }

    private func errorMessage(_ capture: CaptureFiles) throws -> String {
        try String(decoding: capture.errorData(), as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func decode(_ data: Data, target: String, compiler: String) throws -> XcodeProjectMetadata {
        let document = try sourceDocument(data)
        let swiftEntries = try swiftEntries(document, target: target)
        let sourceFiles = swiftEntries.keys.sorted()
        let contexts = try compilerContexts(entries: swiftEntries, sourceFiles: sourceFiles, compiler: compiler)
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
        compiler: String,
    ) throws -> [CompilerContext] {
        var contexts: [CompilerContext] = []
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
            guard let directory = value(after: "-working-directory", in: arguments) else {
                throw SourceSelectionError.invalidXcodeMetadata("source \(source) has no working directory")
            }
            let context = CompilerContext(
                compiler: compiler,
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

    func compiler(buildSettings: [String: String]) throws -> String {
        if let swiftCompiler = nonempty(buildSettings["SWIFT_EXEC"]) {
            return try compiler(path: swiftCompiler, setting: "SWIFT_EXEC")
        }
        guard let toolchain = nonempty(buildSettings["TOOLCHAIN_DIR"]) else {
            throw SourceSelectionError.invalidXcodeMetadata("target has no SWIFT_EXEC or TOOLCHAIN_DIR")
        }
        guard toolchain.hasPrefix("/") else {
            throw SourceSelectionError
                .invalidXcodeMetadata("TOOLCHAIN_DIR does not identify an executable Swift compiler")
        }
        return try compiler(
            path: URL(fileURLWithPath: toolchain, isDirectory: true).appendingPathComponent("usr/bin/swiftc").path,
            setting: "TOOLCHAIN_DIR",
        )
    }

    private func compiler(path: String, setting: String) throws -> String {
        guard path.hasPrefix("/"), FileManager.default.isExecutableFile(atPath: path) else {
            throw SourceSelectionError.invalidXcodeMetadata("\(setting) does not identify an executable Swift compiler")
        }
        return try CanonicalPath().resolvePreservingLastComponent(path)
    }

    private func nonempty(_ value: String?) -> String? {
        guard let value, !value.isEmpty else { return nil }
        return value
    }
}
