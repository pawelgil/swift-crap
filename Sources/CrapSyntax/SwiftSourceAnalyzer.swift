import CrapCore
import Foundation
import SwiftParser
import SwiftSyntax

public struct SwiftSourceAnalyzer: SourceAnalyzing {
    public init() {}

    public func analyze(source: String, file: String) throws -> [Callable] {
        guard !file.isEmpty else {
            throw AnalysisError.missingFile
        }
        let syntax = Parser.parse(source: source)
        guard !syntax.hasError else {
            throw AnalysisError.invalidSyntax
        }
        let normalizedFile = normalize(file)
        guard !normalizedFile.isEmpty else {
            throw AnalysisError.missingFile
        }
        let collector = CallableCollector(file: normalizedFile, syntax: syntax)
        collector.walk(syntax)
        return collector.callables.sorted {
            ($0.span.start, $0.id) < ($1.span.start, $1.id)
        }
    }

    private enum AnalysisError: Error {
        case invalidSyntax
        case missingFile
    }

    private func normalize(_ file: String) -> String {
        let slashed = file.replacingOccurrences(of: "\\", with: "/")
        let components = slashed.split(separator: "/").filter { $0 != "." }
        let prefix = slashed.hasPrefix("/") ? "/" : ""
        return prefix + components.joined(separator: "/")
    }
}
