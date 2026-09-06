import CrapApplication
import Foundation

struct LocalSourceSelector: SourceSelecting {
    private let fileManager: FileManager
    private let packageDescriber: any PackageDescribing
    private let xcodeDescriber: any XcodeProjectDescribing

    init(
        fileManager: FileManager = .default,
        packageDescriber: any PackageDescribing = SwiftPackageDescriber(),
        xcodeDescriber: any XcodeProjectDescribing = XcodeProjectDescriber(),
    ) {
        self.fileManager = fileManager
        self.packageDescriber = packageDescriber
        self.xcodeDescriber = xcodeDescriber
    }

    func select(_ request: SourceSelectionRequest) throws -> SelectedSources {
        let exclusions = try request.exclusions.map(Exclusion.init)
        let selection: RawSelection = switch request.scope {
        case let .file(path):
            try file(path: path, rootOverride: request.rootOverride)
        case let .manifest(file, target):
            try manifest(file: file, target: target)
        case let .package(directory, target):
            try package(directory: directory, target: target, rootOverride: request.rootOverride)
        case let .project(path):
            try project(path: path)
        case let .xcode(request):
            try xcode(request)
        }
        return try normalized(selection, exclusions: exclusions)
    }

    private func file(path: String, rootOverride: String?) throws -> RawSelection {
        let lexicalSource = URL(fileURLWithPath: path).standardizedFileURL
        let lexicalParent = canonical(lexicalSource.deletingLastPathComponent().path)
        let rootedSource = lexicalParent.appendingPathComponent(lexicalSource.lastPathComponent)
        let root = try directory(rootOverride ?? lexicalParent.path)
        if rootOverride == nil {
            try requireContained(rootedSource, in: root)
        }
        let source = canonical(rootedSource.path)
        try requireContained(source, in: root)
        guard fileManager.fileExists(atPath: source.path) else {
            throw SourceSelectionError.missingPath(path)
        }
        guard try source.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true else {
            throw SourceSelectionError.notFile(path)
        }
        return RawSelection(root: root, candidates: [source], filtering: .explicit)
    }

    private func manifest(file: String, target: String) throws -> RawSelection {
        let manifestURL = canonical(file)
        let manifest: SourceManifest
        do {
            manifest = try JSONDecoder().decode(SourceManifest.self, from: Data(contentsOf: manifestURL))
        } catch {
            throw SourceSelectionError.invalidManifest(file)
        }
        guard !manifest.root.hasPrefix("/") else {
            throw SourceSelectionError.invalidManifestRoot(manifest.root)
        }
        guard let paths = manifest.targets[target] else {
            throw SourceSelectionError.target(target)
        }
        if let absolute = paths.first(where: { $0.hasPrefix("/") }) {
            throw SourceSelectionError.invalidManifestSource(absolute)
        }
        let base = manifestURL.deletingLastPathComponent()
        let root: URL
        do {
            root = try directory(base.appendingPathComponent(manifest.root).path)
        } catch {
            throw SourceSelectionError.invalidManifestRoot(manifest.root)
        }
        let candidates = paths.map { root.appendingPathComponent($0) }
        return RawSelection(root: root, candidates: candidates, filtering: .explicit)
    }

    private func package(directory: String, target: String?, rootOverride: String?) throws -> RawSelection {
        let packageRoot = try self.directory(directory)
        let root = try self.directory(rootOverride ?? packageRoot.path)
        let metadata = try packageDescriber.describe(packageAt: packageRoot.path)
        let targets = try productionTargets(metadata.targets, named: target)
        let candidates = targets.flatMap { sourceURLs(for: $0, packageRoot: packageRoot) }
        return RawSelection(root: root, candidates: candidates, filtering: .explicit)
    }

    private func project(path: String) throws -> RawSelection {
        let root = try directory(path)
        return RawSelection(root: root, candidates: [root], filtering: .project)
    }

    private func xcode(_ request: XcodeSelection) throws -> RawSelection {
        let project = try directory(request.project)
        guard project.pathExtension == "xcodeproj" else {
            throw SourceSelectionError.invalidXcodeProject(request.project)
        }
        let root = project.deletingLastPathComponent()
        let resolved = XcodeSelection(
            project: project.path,
            scheme: request.scheme,
            target: request.target,
            configuration: request.configuration,
            destination: request.destination,
        )
        let metadata = try xcodeDescriber.describe(resolved)
        return RawSelection(
            root: root,
            candidates: metadata.sourceFiles.map { URL(fileURLWithPath: $0) },
            filtering: .explicit,
        )
    }

    private func productionTargets(
        _ targets: [PackageMetadata.Target],
        named name: String?,
    ) throws -> [PackageMetadata.Target] {
        let production = targets.filter { !["binary", "plugin", "system-target", "test"].contains($0.type) }
        guard let name else {
            return production
        }
        let matches = production.filter { $0.name == name }
        guard matches.count == 1 else {
            throw SourceSelectionError.target(name)
        }
        return matches
    }

    private func sourceURLs(for target: PackageMetadata.Target, packageRoot: URL) -> [URL] {
        guard let path = target.path, let sources = target.sources else {
            return []
        }
        let targetRoot = packageRoot.appendingPathComponent(path)
        return sources.map { targetRoot.appendingPathComponent($0) }
    }

    private func normalized(_ selection: RawSelection, exclusions: [Exclusion]) throws -> SelectedSources {
        var visited = Set<String>()
        let files = try selection.candidates.flatMap {
            try swiftFiles(
                at: $0,
                root: selection.root,
                filtering: selection.filtering,
                exclusions: exclusions,
                visited: &visited,
            )
        }
        let paths = try files.map { try (relative: relative($0, to: selection.root), url: $0) }
        let selected = Dictionary(grouping: paths, by: \.relative).map { relativePath, matches in
            SelectedSource(path: matches[0].url.path, relativePath: relativePath)
        }.sorted { $0.relativePath < $1.relativePath }
        return SelectedSources(root: selection.root.path, files: selected)
    }

    private func swiftFiles(
        at candidate: URL,
        root: URL,
        filtering: Filtering,
        exclusions: [Exclusion],
        visited: inout Set<String>,
    ) throws -> [URL] {
        if try isExcludedBeforeResolution(candidate, root: root, filtering: filtering, exclusions: exclusions) {
            return []
        }
        let resolved = canonical(candidate.path)
        guard fileManager.fileExists(atPath: resolved.path) else {
            throw SourceSelectionError.missingPath(candidate.path)
        }
        try requireContained(resolved, in: root)
        let relativePath = try relative(resolved, to: root)
        if !filtering.includes(directory: relativePath)
            || exclusions.contains(where: { $0.matches(relativePath) })
        {
            return []
        }
        let values = try resolved.resourceValues(forKeys: [.isDirectoryKey, .isRegularFileKey])
        if values.isDirectory == true {
            guard filtering.includes(directory: relativePath), visited.insert(resolved.path).inserted else {
                return []
            }
            return try fileManager.contentsOfDirectory(at: resolved, includingPropertiesForKeys: nil)
                .sorted { $0.path < $1.path }.flatMap {
                    try swiftFiles(at: $0, root: root, filtering: filtering, exclusions: exclusions, visited: &visited)
                }
        }
        guard values.isRegularFile == true,
              resolved.pathExtension == "swift",
              filtering.includes(file: relativePath)
        else {
            return []
        }
        return [resolved]
    }

    private func isExcludedBeforeResolution(
        _ candidate: URL,
        root: URL,
        filtering: Filtering,
        exclusions: [Exclusion],
    ) throws -> Bool {
        let lexical = candidate.standardizedFileURL
        let relativePath = try relative(lexical, to: root)
        return !filtering.includes(directory: relativePath) || exclusions.contains { $0.matches(relativePath) }
    }

    private func canonical(_ path: String) -> URL {
        URL(fileURLWithPath: path).standardizedFileURL.resolvingSymlinksInPath()
    }

    private func directory(_ path: String) throws -> URL {
        let url = canonical(path)
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            throw SourceSelectionError.missingPath(path)
        }
        return url
    }

    private func requireContained(_ path: URL, in root: URL) throws {
        let contained = root.path == "/" ? path.path.hasPrefix("/") : path.path == root.path || path.path
            .hasPrefix(root.path + "/")
        guard contained else {
            throw SourceSelectionError.escapedRoot(path.path)
        }
    }

    private func relative(_ path: URL, to root: URL) throws -> String {
        try requireContained(path, in: root)
        if path.path == root.path {
            return ""
        }
        let count = root.path == "/" ? 1 : root.path.count + 1
        return String(path.path.dropFirst(count))
    }
}
