import CrapApplication
import Foundation

struct LocalCompilerContextLoader: CompilerContextLoading {
    func load(_ request: CaptureRequest, root: String) throws -> [CompilerContext] {
        let contexts: [CompilerContext]
        if let xcode = request.xcode {
            contexts = try XcodeProjectDescriber().describe(
                xcode,
                matchingXcodebuildCommand: request.command,
                workingDirectory: root,
            ).compilerContexts
        } else if let path = request.buildDescription {
            contexts = try SwiftPMCompilerContexts().read(
                at: CanonicalPath().resolve(path, relativeTo: root),
                root: root,
            )
        } else if let path = request.buildContext {
            let url = try URL(fileURLWithPath: CanonicalPath().resolve(path, relativeTo: root))
            contexts = try JSONDecoder().decode([CompilerContext].self, from: Data(contentsOf: url))
        } else {
            throw ProvenanceError.invalid("capture requires --build-description or --build-context")
        }
        guard !contexts.isEmpty else {
            throw ProvenanceError.invalid("compiler context is empty")
        }
        return try contexts.map { try normalized($0, root: root) }
    }

    private func normalized(_ context: CompilerContext, root: String) throws -> CompilerContext {
        let directory = try CanonicalPath().resolve(context.directory, relativeTo: root)
        let compiler = try CanonicalPath().resolvePreservingLastComponent(context.compiler, relativeTo: directory)
        let sources = try context.sources.map { try CanonicalPath().resolve($0, relativeTo: directory) }
        guard !context.moduleName.isEmpty, !sources.isEmpty else {
            throw ProvenanceError.invalid("compiler context is incomplete")
        }
        return CompilerContext(
            compiler: compiler,
            arguments: context.arguments,
            directory: directory,
            sources: sources,
            moduleName: context.moduleName,
        )
    }
}
