import CrapApplication
import SwiftIfConfig
import SwiftSyntax

struct CompilerBuildConfiguration: BuildConfiguration {
    let targetPointerBitWidth: Int
    let targetAtomicBitWidths: [Int]
    let endianness: Endianness
    let languageVersion: VersionTuple
    let compilerVersion: VersionTuple
    private let probe: any CompilerConditionEvaluating

    init(context: CompilerContext) throws {
        try self.init(probe: CompilerProbe(context: context))
    }

    init(probe: any CompilerConditionEvaluating) throws {
        self.probe = probe
        let pointerWidths = try [16, 32, 64, 128].filter { try probe.evaluate("_pointerBitWidth(_\($0))") }
        guard pointerWidths.count == 1, let width = pointerWidths.first else {
            throw ProvenanceError.invalid("unknown compiler target pointer width")
        }
        targetPointerBitWidth = width
        targetAtomicBitWidths = try [8, 16, 32, 64, 128].filter { try probe.evaluate("_hasAtomicBitWidth(_\($0))") }
        let littleEndian = try probe.evaluate("_endian(little)")
        let bigEndian = try probe.evaluate("_endian(big)")
        guard littleEndian != bigEndian else { throw ProvenanceError.invalid("unknown compiler target endianness") }
        endianness = littleEndian ? .little : .big
        languageVersion = try Self.version(kind: "swift", componentCount: 3, probe: probe)
        compilerVersion = try Self.version(kind: "compiler", componentCount: 5, probe: probe)
    }

    func isCustomConditionSet(name: String) throws -> Bool {
        try probe.evaluate(name)
    }

    func hasFeature(name: String) throws -> Bool {
        try probe.evaluate("hasFeature(\(name))")
    }

    func hasAttribute(name: String) throws -> Bool {
        try probe.evaluate("hasAttribute(\(name))")
    }

    func isActiveTargetOS(name: String) throws -> Bool {
        try probe.evaluate("os(\(name))")
    }

    func isActiveTargetArchitecture(name: String) throws -> Bool {
        try probe.evaluate("arch(\(name))")
    }

    func isActiveTargetEnvironment(name: String) throws -> Bool {
        try probe.evaluate("targetEnvironment(\(name))")
    }

    func isActiveTargetRuntime(name: String) throws -> Bool {
        try probe.evaluate("_runtime(\(name))")
    }

    func isActiveTargetPointerAuthentication(name: String) throws -> Bool {
        try probe.evaluate("_ptrauth(\(name))")
    }

    func isActiveTargetObjectFormat(name: String) throws -> Bool {
        try probe.evaluate("objectFormat(\(name))")
    }

    func canImport(importPath: [(TokenSyntax, String)], version: CanImportVersion) throws -> Bool {
        let path = importPath.map(\.1).joined(separator: ".")
        let suffix = switch version {
        case .unversioned: ""
        case let .version(value): ", _version: \(value)"
        case let .underlyingVersion(value): ", _underlyingVersion: \(value)"
        }
        return try probe.evaluate("canImport(\(path)\(suffix))")
    }

    private static func version(
        kind: String,
        componentCount: Int,
        probe: any CompilerConditionEvaluating,
    ) throws -> VersionTuple {
        var components: [Int] = []
        for _ in 0 ..< componentCount {
            var low = 0
            var high = 1
            while try probe.evaluate(versionCondition(kind: kind, components: components + [high])) {
                low = high
                guard high <= Int.max / 2 else {
                    throw ProvenanceError.invalid("compiler \(kind) version component is unrepresentable")
                }
                high *= 2
            }
            while low + 1 < high {
                let middle = low + (high - low) / 2
                let candidate = (components + [middle]).map(String.init).joined(separator: ".")
                if try probe.evaluate("\(kind)(>=\(candidate))") { low = middle } else { high = middle }
            }
            components.append(low)
        }
        return VersionTuple(components: components)
    }

    private static func versionCondition(kind: String, components: [Int]) -> String {
        "\(kind)(>=\(components.map(String.init).joined(separator: ".")))"
    }
}
