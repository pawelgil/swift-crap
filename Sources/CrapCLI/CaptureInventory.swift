import CrapApplication
import CrapCore
import CrapSyntax
import Foundation

struct CaptureInventory: CallableInventoryCapturing {
    private let makeAnalyzer: (CompilerContext) throws -> any SourceAnalyzing

    init() {
        makeAnalyzer = { context in
            try SwiftSourceAnalyzer(configuration: CompilerBuildConfiguration(context: context))
        }
    }

    init(makeAnalyzer: @escaping (CompilerContext) throws -> any SourceAnalyzing) {
        self.makeAnalyzer = makeAnalyzer
    }

    func read(contexts: [CompilerContext], root: String, inputs: [String: String]) throws -> [Callable] {
        let claims = try analyze(contexts: contexts, root: root, inputs: inputs)
        let result = try reconcile(claims)
        guard !result.isEmpty else { throw ProvenanceError.invalid("no captured callable inventory") }
        return result.sorted(by: callableOrder)
    }

    private func analyze(
        contexts: [CompilerContext],
        root: String,
        inputs: [String: String],
    ) throws -> [String: [[Callable]]] {
        var claims: [String: [[Callable]]] = [:]
        var sourceText: [String: String] = [:]
        var seenContexts: [CompilerContext] = []
        for context in contexts {
            guard !seenContexts.contains(context) else { continue }
            seenContexts.append(context)
            let sources = relevantSources(context: context, root: root, inputs: inputs)
            guard !sources.isEmpty else { continue }
            let analyzer = try makeAnalyzer(context)
            for path in sources {
                let source = try sourceText[path] ?? String(contentsOfFile: path, encoding: .utf8)
                sourceText[path] = source
                let file = String(path.dropFirst(root.count + 1))
                try claims[path, default: []]
                    .append(analyzer.analyze(source: source, file: file).sorted(by: callableOrder))
            }
        }
        return claims
    }

    private func relevantSources(
        context: CompilerContext,
        root: String,
        inputs: [String: String],
    ) -> [String] {
        let directory = URL(fileURLWithPath: context.directory, isDirectory: true)
        return Set(context.sources.map {
            URL(fileURLWithPath: $0, relativeTo: directory).standardizedFileURL.resolvingSymlinksInPath().path
        })
        .filter { $0.hasPrefix(root + "/") }
        .filter { inputs[String($0.dropFirst(root.count + 1))] != nil }
        .sorted()
    }

    private func reconcile(_ claims: [String: [[Callable]]]) throws -> [Callable] {
        var result: [Callable] = []
        for path in claims.keys.sorted() {
            guard let inventories = claims[path], let first = inventories.first,
                  inventories.dropFirst().allSatisfy({ $0 == first })
            else { throw ProvenanceError.invalid("ambiguous compiler contexts: \(path)") }
            result += first
        }
        return result
    }

    private func callableOrder(_ lhs: Callable, _ rhs: Callable) -> Bool {
        (lhs.file, lhs.span.start, lhs.id) < (rhs.file, rhs.span.start, rhs.id)
    }
}
