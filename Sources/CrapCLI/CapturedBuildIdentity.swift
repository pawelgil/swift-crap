import CrapApplication
import Foundation

struct CapturedBuildIdentity {
    func read(receipt: CaptureReceipt, selection: SourceSelectionRequest) throws -> String {
        let document = try Document(
            root: CanonicalPath().resolve(receipt.root),
            scope: scope(selection.scope),
            rootOverride: selection.rootOverride.map { try CanonicalPath().resolve($0) },
            exclusions: selection.exclusions.sorted(),
            contexts: contexts(receipt.contexts),
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return try ContentDigest().hash(encoder.encode(document))
    }

    private func scope(_ scope: SourceScope) throws -> Scope {
        switch scope {
        case let .file(path):
            try Scope(kind: "file", path: CanonicalPath().resolve(path))
        case let .manifest(file, target):
            try Scope(kind: "manifest", path: CanonicalPath().resolve(file), target: target)
        case let .package(directory, target):
            try Scope(kind: "package", path: CanonicalPath().resolve(directory), target: target)
        case let .project(path):
            try Scope(kind: "project", path: CanonicalPath().resolve(path))
        case let .xcode(selection):
            try Scope(
                kind: "xcode",
                path: CanonicalPath().resolve(selection.project),
                target: selection.target,
                scheme: selection.scheme,
                configuration: selection.configuration,
                destination: selection.destination,
            )
        }
    }

    private func contexts(_ contexts: [CompilerContext]) throws -> [Context] {
        try contexts.map { context in
            try Context(
                compiler: context.compiler,
                moduleName: context.moduleName,
                directory: context.directory,
                arguments: CompilerProbeArguments().prepare(context.arguments),
            )
        }.sorted { lhs, rhs in
            (lhs.compiler, lhs.moduleName, lhs.directory, lhs.arguments.joined(separator: "\0"))
                < (rhs.compiler, rhs.moduleName, rhs.directory, rhs.arguments.joined(separator: "\0"))
        }
    }

    private struct Document: Encodable {
        let root: String
        let scope: Scope
        let rootOverride: String?
        let exclusions: [String]
        let contexts: [Context]
    }

    private struct Scope: Encodable {
        let kind: String
        let path: String
        let target: String?
        let scheme: String?
        let configuration: String?
        let destination: String?

        init(
            kind: String,
            path: String,
            target: String? = nil,
            scheme: String? = nil,
            configuration: String? = nil,
            destination: String? = nil,
        ) {
            self.kind = kind
            self.path = path
            self.target = target
            self.scheme = scheme
            self.configuration = configuration
            self.destination = destination
        }
    }

    private struct Context: Encodable {
        let compiler: String
        let moduleName: String
        let directory: String
        let arguments: [String]
    }
}
