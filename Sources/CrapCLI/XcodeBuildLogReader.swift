import CrapApplication
import Foundation

struct XcodeBuildLogReader {
    func read(
        at path: String,
        project: String,
        settings: XcodeResolvedBuildSettings,
        target: String,
    ) throws -> XcodeProjectMetadata {
        let data = try output(path)
        return try decode(
            data,
            project: project,
            settings: settings,
            target: target,
        )
    }

    func decode(
        _ data: Data,
        project: String,
        settings: XcodeResolvedBuildSettings,
        target: String,
    ) throws -> XcodeProjectMetadata {
        let document = try document(data)
        let projectName = URL(fileURLWithPath: project).deletingPathExtension().lastPathComponent
        let contexts = try contexts(
            document,
            project: projectName,
            settings: settings,
            target: target,
        )
        guard !contexts.isEmpty else {
            throw SourceSelectionError.invalidXcodeMetadata(
                "result bundle has no SwiftDriver invocation for target \(target); rebuild the target during capture",
            )
        }
        guard contexts.count == 1 else {
            throw SourceSelectionError.invalidXcodeMetadata(
                "result bundle has ambiguous SwiftDriver invocations for target \(target)",
            )
        }
        let sources = Set(contexts.flatMap(\.sources)).sorted()
        return XcodeProjectMetadata(sourceFiles: sources, compilerContexts: contexts)
    }

    private func document(_ data: Data) throws -> Any {
        let document: Any
        do {
            document = try JSONSerialization.jsonObject(with: data)
        } catch {
            throw SourceSelectionError.invalidXcodeMetadata("cannot decode Xcode build log: \(error)")
        }
        return document
    }

    private func contexts(
        _ document: Any,
        project: String,
        settings: XcodeResolvedBuildSettings,
        target: String,
    ) throws -> [CompilerContext] {
        let details = values(named: "commandDetails", in: document)
            .filter { $0.contains("(in target '\(target)' from project '\(project)')") }
        let decoded: [CompilerContext] = try details.compactMap {
            try context(
                $0,
                settings: settings,
                target: target,
            )
        }
        return decoded.reduce(into: [CompilerContext]()) { result, context in
            if !result.contains(context) { result.append(context) }
        }
    }

    private func output(_ path: String) throws -> Data {
        let capture = try CaptureFiles()
        defer { capture.remove() }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
        process.arguments = ["xcresulttool", "get", "log", "--path", path, "--type", "build", "--compact"]
        process.standardOutput = capture.output
        process.standardError = capture.error
        try process.run()
        process.waitUntilExit()
        capture.close()
        guard process.terminationStatus == 0 else {
            let message = try String(decoding: capture.errorData(), as: UTF8.self)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            throw SourceSelectionError.xcodeDescription("cannot read result bundle build log: \(message)")
        }
        return try capture.outputData()
    }

    private func context(
        _ details: String,
        settings: XcodeResolvedBuildSettings,
        target: String,
    ) throws -> CompilerContext? {
        guard let rawArguments = try driverArguments(details) else { return nil }
        guard try matchesTarget(rawArguments, settings: settings) else { return nil }
        return try context(rawArguments, target: target, compiler: settings.compiler)
    }

    private func matchesTarget(_ rawArguments: [String], settings: XcodeResolvedBuildSettings) throws -> Bool {
        let arguments = Array(rawArguments.dropFirst())
        guard let workingDirectory = value(after: "-working-directory", in: arguments),
              value(after: "-module-name", in: arguments) == settings.moduleName
        else { return false }
        let canonical = CanonicalPath()
        guard try canonical.resolve(workingDirectory) == settings.projectDirectory else { return false }
        let outputs = values(after: "-output-file-map", in: arguments)
            + values(after: "-emit-module-path", in: arguments)
        guard !outputs.isEmpty else { return false }
        return try outputs.allSatisfy {
            let path = try canonical.resolve($0, relativeTo: workingDirectory)
            return path.hasPrefix(settings.objectFileDirectory + "/")
        }
    }

    private func driverArguments(_ details: String) throws -> [String]? {
        let prefix = "builtin-SwiftDriver -- "
        guard let line = details.split(separator: "\n").first(where: {
            $0.trimmingCharacters(in: .whitespaces).hasPrefix(prefix)
        }) else { return nil }
        let command = line.trimmingCharacters(in: .whitespaces)
        return try ShellArguments().parse(String(command.dropFirst(prefix.count)))
    }

    private func context(
        _ rawArguments: [String],
        target: String,
        compiler: String,
    ) throws -> CompilerContext {
        guard let loggedCompiler = rawArguments.first else {
            throw SourceSelectionError.invalidXcodeMetadata("target \(target) has an empty SwiftDriver invocation")
        }
        let compilerArguments = Array(rawArguments.dropFirst())
        guard let directory = value(after: "-working-directory", in: compilerArguments),
              let moduleName = value(after: "-module-name", in: compilerArguments)
        else {
            throw SourceSelectionError.invalidXcodeMetadata(
                "target \(target) SwiftDriver invocation is missing module or working directory",
            )
        }
        try validate(loggedCompiler: loggedCompiler, resolvedCompiler: compiler, directory: directory, target: target)
        let arguments = try expandResponses(compilerArguments, directory: directory)
        let sources = arguments.filter { $0.hasSuffix(".swift") }
        guard !sources.isEmpty else {
            throw SourceSelectionError.invalidXcodeMetadata("target \(target) SwiftDriver invocation has no sources")
        }
        return CompilerContext(
            compiler: compiler,
            arguments: arguments,
            directory: directory,
            sources: sources,
            moduleName: moduleName,
        )
    }

    private func validate(
        loggedCompiler: String,
        resolvedCompiler: String,
        directory: String,
        target: String,
    ) throws {
        let canonical = CanonicalPath()
        let logged = try canonical.resolvePreservingLastComponent(loggedCompiler, relativeTo: directory)
        let resolved = try canonical.resolvePreservingLastComponent(resolvedCompiler, relativeTo: directory)
        guard logged == resolved else {
            throw SourceSelectionError.invalidXcodeMetadata(
                "target \(target) SwiftDriver compiler differs from resolved build settings",
            )
        }
    }

    private func expandResponses(_ arguments: [String], directory: String) throws -> [String] {
        var result: [String] = []
        for argument in arguments {
            guard argument.hasPrefix("@") else {
                result.append(argument)
                continue
            }
            let path = try CanonicalPath().resolve(String(argument.dropFirst()), relativeTo: directory)
            let expanded = try ShellArguments().parse(responseContents(path))
            guard !expanded.contains(where: { $0.hasPrefix("@") }) else {
                throw SourceSelectionError.invalidXcodeMetadata("nested Swift response file in \(path)")
            }
            result += expanded
        }
        return result
    }

    private func responseContents(_ path: String) throws -> String {
        do {
            return try String(contentsOfFile: path, encoding: .utf8)
        } catch {
            throw SourceSelectionError.invalidXcodeMetadata("cannot read Swift response file \(path): \(error)")
        }
    }

    private func values(named name: String, in value: Any) -> [String] {
        if let dictionary = value as? [String: Any] {
            let own = (dictionary[name] as? String).map { [$0] } ?? []
            return own + dictionary.values.flatMap { values(named: name, in: $0) }
        }
        if let array = value as? [Any] {
            return array.flatMap { values(named: name, in: $0) }
        }
        return []
    }

    private func value(after option: String, in arguments: [String]) -> String? {
        guard let index = arguments.lastIndex(of: option) else { return nil }
        let next = arguments.index(after: index)
        return next < arguments.endIndex ? arguments[next] : nil
    }

    private func values(after option: String, in arguments: [String]) -> [String] {
        arguments.indices.compactMap { index in
            guard arguments[index] == option else { return nil }
            let next = arguments.index(after: index)
            return next < arguments.endIndex ? arguments[next] : nil
        }
    }
}
