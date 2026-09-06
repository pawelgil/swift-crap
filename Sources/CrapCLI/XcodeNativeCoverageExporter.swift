import CrapApplication
import Foundation

struct XcodeNativeCoverageExporter: XcodeNativeCoverageExporting {
    private let productResolver: any XcodeBuildProductResolving
    private let runner: any XcodeNativeCoverageCommandRunning

    init(
        runner: any XcodeNativeCoverageCommandRunning = LocalXcodeNativeCoverageCommandRunner(),
        productResolver: any XcodeBuildProductResolving = LocalXcodeBuildProductResolver(),
    ) {
        self.runner = runner
        self.productResolver = productResolver
    }

    func export(
        resultBundle: String,
        selection: XcodeSelection,
        contexts: [CompilerContext],
        command: [String],
        root: String,
    ) throws -> Data {
        let sources = try selectedSources(contexts: contexts, root: root)
        let product = try productResolver.product(selection: selection, command: command, workingDirectory: root)
        let report = try decodeReport(run(["xccov", "view", "--report", "--json", resultBundle]))
        let target = try selectedTarget(report.targets, product: product, sources: sources)
        let exportSources = try Set(target.files.compactMap { file -> String? in
            let path = try CanonicalPath().resolve(file.path)
            return sources.contains(path) ? path : nil
        })
        let archive = try decodeArchive(run(["xccov", "view", "--archive", "--json", resultBundle]))
        let device = try resolvedDevice(
            run(["xcresulttool", "get", "test-results", "summary", "--path", resultBundle, "--compact"]),
            command: command,
        )
        let profile = try profilePath(product: target.buildProductPath, device: device)
        let candidates = binaryCandidates(target.buildProductPath)
        var successes: [(path: String, data: Data)] = []
        var failures: [String] = []
        for candidate in candidates {
            do {
                let arguments = ["llvm-cov", "export", candidate, "-instr-profile=\(profile)", "--sources"]
                    + exportSources.sorted()
                let data = try run(arguments)
                let scoped = try XcodeCoverageCompactor().compact(data, sources: exportSources)
                try validate(scoped, target: target, archive: archive, sources: sources)
                successes.append((candidate, scoped))
            } catch {
                failures.append("\(candidate): \(error)")
            }
        }
        guard let first = successes.first else {
            throw XcodeNativeCoverageExportError.candidateFailures(failures)
        }
        guard successes.allSatisfy({ $0.data == first.data }) else {
            throw XcodeNativeCoverageExportError.conflictingCandidates(successes.map(\.path))
        }
        return first.data
    }

    private func selectedSources(contexts: [CompilerContext], root: String) throws -> Set<String> {
        let canonicalRoot = try CanonicalPath().resolve(root)
        let prefix = canonicalRoot == "/" ? "/" : canonicalRoot + "/"
        let paths = try contexts.flatMap { context in
            try context.sources.map { try CanonicalPath().resolve($0, relativeTo: context.directory) }
        }
        let authored = paths.filter { $0 == canonicalRoot || $0.hasPrefix(prefix) }
        guard !authored.isEmpty else {
            throw XcodeNativeCoverageExportError.invalidEvidence("compiler contexts have no sources")
        }
        return Set(authored)
    }

    private func selectedTarget(
        _ targets: [ReportTarget],
        product: String,
        sources: Set<String>,
    ) throws -> ReportTarget {
        let expected = try CanonicalPath().resolve(product)
        let matches = try targets.filter { target in
            guard try CanonicalPath().resolve(target.buildProductPath) == expected else { return false }
            let paths = try Set(target.files.map { try CanonicalPath().resolve($0.path) })
            return !sources.isDisjoint(with: paths)
        }
        guard matches.count == 1, let target = matches.first else {
            throw XcodeNativeCoverageExportError.invalidEvidence(
                "xccov report does not identify exactly one selected build product intersecting selected sources",
            )
        }
        return target
    }

    private func resolvedDevice(_ data: Data, command: [String]) throws -> String {
        let summary: ResultSummary
        do {
            summary = try JSONDecoder().decode(ResultSummary.self, from: data)
        } catch {
            throw XcodeNativeCoverageExportError.invalidEvidence("cannot decode result destination: \(error)")
        }
        let devices = Set(summary.devicesAndConfigurations.map(\.device.deviceId))
        if let requested = destinationDevice(in: command) {
            guard devices.contains(requested) else {
                throw XcodeNativeCoverageExportError.invalidEvidence(
                    "result destination does not match xcodebuild destination id \(requested)",
                )
            }
            return try validDevice(requested)
        }
        guard devices.count == 1, let device = devices.first else {
            throw XcodeNativeCoverageExportError.invalidEvidence("result bundle has ambiguous destination device ids")
        }
        return try validDevice(device)
    }

    private func validDevice(_ device: String) throws -> String {
        guard !device.isEmpty,
              device != ".",
              device != "..",
              !device.contains("/"),
              !device.contains("\\")
        else {
            throw XcodeNativeCoverageExportError.invalidEvidence("result bundle has invalid destination device id")
        }
        return device
    }

    private func destinationDevice(in command: [String]) -> String? {
        command.indices.compactMap { index -> String? in
            guard command[index] == "-destination" else { return nil }
            let valueIndex = command.index(after: index)
            guard valueIndex < command.endIndex else { return nil }
            return command[valueIndex].split(separator: ",").lazy
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .first { $0.hasPrefix("id=") }
                .map { String($0.dropFirst(3)) }
        }.last ?? nil
    }

    private func profilePath(product: String, device: String) throws -> String {
        let productURL = try URL(fileURLWithPath: CanonicalPath().resolve(product))
        let components = productURL.pathComponents
        guard let build = components.indices.last(where: {
            components[$0] == "Build" && components.index(after: $0) < components.endIndex
                && components[components.index(after: $0)] == "Products"
        }) else {
            throw XcodeNativeCoverageExportError.invalidEvidence("build product is not inside Build/Products")
        }
        let derived = components[...build].reduce(URL(fileURLWithPath: "/")) { url, component in
            component == "/" ? url : url.appendingPathComponent(component)
        }
        return derived.appendingPathComponent("ProfileData")
            .appendingPathComponent(device)
            .appendingPathComponent("Coverage.profdata").path
    }

    private func binaryCandidates(_ product: String) -> [String] {
        let direct = URL(fileURLWithPath: product).standardizedFileURL.path
        let container = URL(fileURLWithPath: direct).deletingLastPathComponent()
        let appExecutable = container.pathExtension == "app"
            || container.lastPathComponent == "MacOS"
            && container.deletingLastPathComponent().lastPathComponent == "Contents"
            && container.deletingLastPathComponent().deletingLastPathComponent().pathExtension == "app"
        guard appExecutable else { return [direct] }
        return [
            direct,
            container.appendingPathComponent(URL(fileURLWithPath: direct).lastPathComponent + ".debug.dylib").path,
        ]
    }

    private func validate(
        _ data: Data,
        target: ReportTarget,
        archive: [String: [ArchiveLine]],
        sources: Set<String>,
    ) throws {
        try XcodeCoverageEvidenceValidator().validate(
            data,
            files: target.files.map {
                XcodeCoverageEvidenceValidator.File(
                    coveredLines: $0.coveredLines,
                    executableLines: $0.executableLines,
                    functions: $0.functions.map {
                        XcodeCoverageEvidenceValidator.Function(
                            anchorLine: $0.lineNumber,
                            coveredLines: $0.coveredLines,
                            executableLines: $0.executableLines,
                        )
                    },
                    path: $0.path,
                )
            },
            archive: archive.mapValues {
                $0.map {
                    XcodeCoverageEvidenceValidator.ArchiveLine(
                        executionCount: $0.executionCount,
                        isExecutable: $0.isExecutable,
                        line: $0.line,
                        subranges: $0.subranges?.map {
                            XcodeCoverageEvidenceValidator.ArchiveSubrange(
                                column: $0.column,
                                executionCount: $0.executionCount,
                                length: $0.length,
                            )
                        },
                    )
                }
            },
            sources: sources,
        )
    }

    private func run(_ arguments: [String]) throws -> Data {
        let result = try runner.run(arguments: arguments)
        guard result.status == 0 else {
            let message = String(decoding: result.error, as: UTF8.self)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            throw XcodeNativeCoverageExportError.commandFailed(
                "xcrun \(arguments.joined(separator: " ")) exited \(result.status): \(message)",
            )
        }
        return result.output
    }

    private func decodeReport(_ data: Data) throws -> Report {
        do { return try JSONDecoder().decode(Report.self, from: data) }
        catch { throw XcodeNativeCoverageExportError.invalidEvidence("cannot decode xccov report: \(error)") }
    }

    private func decodeArchive(_ data: Data) throws -> [String: [ArchiveLine]] {
        do { return try JSONDecoder().decode([String: [ArchiveLine]].self, from: data) }
        catch { throw XcodeNativeCoverageExportError.invalidEvidence("cannot decode xccov archive: \(error)") }
    }

    private struct Report: Decodable {
        let targets: [ReportTarget]
    }

    private struct ReportTarget: Decodable {
        let buildProductPath: String
        let files: [ReportFile]
    }

    private struct ReportFile: Decodable {
        let coveredLines: Int
        let executableLines: Int
        let functions: [ReportFunction]
        let path: String
    }

    private struct ReportFunction: Decodable {
        let coveredLines: Int
        let executableLines: Int
        let lineNumber: Int
    }

    private struct ArchiveLine: Decodable {
        let executionCount: Int?
        let isExecutable: Bool
        let line: Int
        let subranges: [ArchiveSubrange]?
    }

    private struct ArchiveSubrange: Decodable {
        let column: Int
        let executionCount: Int
        let length: Int
    }

    private struct ResultSummary: Decodable {
        let devicesAndConfigurations: [DeviceConfiguration]
    }

    private struct DeviceConfiguration: Decodable {
        let device: Device
    }

    private struct Device: Decodable {
        let deviceId: String
    }
}
