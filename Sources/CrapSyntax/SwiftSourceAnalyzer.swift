import CrapCore
import Foundation
import SwiftIfConfig
@_spi(ExperimentalLanguageFeatures) import SwiftParser
import SwiftParserDiagnostics
import SwiftSyntax

public struct SwiftSourceAnalyzer: SourceAnalyzing {
    private let borrowAndMutateEnabled: (() throws -> Bool)?
    private let configuredRegions: ((SourceFileSyntax) -> ConfiguredRegions)?
    private let parse: (String) throws -> SourceFileSyntax

    public init() {
        borrowAndMutateEnabled = nil
        configuredRegions = nil
        parse = { Parser.parse(source: $0) }
    }

    public init(configuration: some BuildConfiguration) {
        borrowAndMutateEnabled = {
            try configuration.hasFeature(name: "BorrowAndMutateAccessors")
        }
        configuredRegions = { syntax in
            syntax.configuredRegions(in: configuration)
        }
        parse = { source in
            let features = try Self.parserFeatures(in: configuration)
            let version = Self.parserSwiftVersion(for: configuration.languageVersion)
            let bytes = Array(source.utf8)
            return bytes.withUnsafeBufferPointer {
                Parser.parse(source: $0, swiftVersion: version, experimentalFeatures: features)
            }
        }
    }

    public func analyze(source: String, file: String) throws -> [Callable] {
        guard !file.isEmpty else {
            throw AnalysisError.missingFile
        }
        let syntax = try parse(source)
        let normalizedFile = normalize(file)
        guard !normalizedFile.isEmpty else {
            throw AnalysisError.missingFile
        }
        let regions = configuredRegions?(syntax)
        if let regions, !regions.diagnostics.isEmpty {
            throw AnalysisError.invalidConditionalCompilation(
                regions.diagnostics.map { String(describing: $0) },
            )
        }
        let diagnostics = ParseDiagnosticsGenerator.diagnostics(for: syntax)
        let relevantDiagnostics = diagnostics.filter { diagnostic in
            guard let regions else { return true }
            if case .unparsed = regions.state(at: diagnostic.position) {
                return false
            }
            return true
        }
        if !relevantDiagnostics.isEmpty || syntax.hasError && diagnostics.isEmpty {
            throw AnalysisError.invalidSyntax(relevantDiagnostics.map(\.debugDescription))
        }
        let collector = try CallableCollector(
            file: normalizedFile,
            syntax: syntax,
            configuredRegions: regions,
            borrowAndMutateEnabled: borrowAndMutateEnabled?() ?? true,
        )
        collector.walk(syntax)
        return collector.callables.sorted {
            ($0.span.start, $0.id) < ($1.span.start, $1.id)
        }
    }

    private enum AnalysisError: Error {
        case invalidConditionalCompilation([String])
        case invalidSyntax([String])
        case missingFile
    }

    private static let parserFeatureNames = [
        "BorrowAndMutateAccessors",
        "CoroutineAccessors",
        "DefaultIsolationPerFile",
        "DoExpressions",
        "KeypathWithMethodMembers",
        "NonescapableTypes",
        "OldOwnershipOperatorSpellings",
        "ReferenceBindings",
        "ThenStatements",
        "TrailingComma",
    ]

    private static func parserFeatures(in configuration: some BuildConfiguration) throws -> Parser
        .ExperimentalFeatures
    {
        var result: Parser.ExperimentalFeatures = []
        for name in parserFeatureNames where try configuration.hasFeature(name: name) {
            if let feature = Parser.ExperimentalFeatures(name: name) {
                result.insert(feature)
            }
        }
        return result
    }

    private static func parserSwiftVersion(for version: VersionTuple) -> Parser.SwiftVersion {
        if version < VersionTuple(5) {
            return .v4
        }
        if version < VersionTuple(6) {
            return .v5
        }
        if version < VersionTuple(7) {
            return .v6
        }
        return Parser.defaultSwiftVersion
    }

    private func normalize(_ file: String) -> String {
        let slashed = file.replacingOccurrences(of: "\\", with: "/")
        let components = slashed.split(separator: "/").filter { $0 != "." }
        let prefix = slashed.hasPrefix("/") ? "/" : ""
        return prefix + components.joined(separator: "/")
    }
}
