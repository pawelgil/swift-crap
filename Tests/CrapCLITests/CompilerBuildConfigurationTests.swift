@testable import CrapCLI
import SwiftIfConfig
import SwiftSyntax
import Testing

struct CompilerBuildConfigurationTests {
    @Test func `reads complete compiler truth from probe`() throws {
        let probe = VersionProbe(language: VersionTuple(6, 0, 0), compiler: VersionTuple(6, 3, 1, 128, 108))

        let result = try CompilerBuildConfiguration(probe: probe)

        #expect(result.targetPointerBitWidth == 64)
        #expect(result.targetAtomicBitWidths == [32, 64])
        #expect(result.endianness == .little)
        #expect(result.languageVersion.components == [6, 0, 0])
        #expect(result.compilerVersion.components == [6, 3, 1, 128, 108])
    }

    @Test func `unavailable compiler truth rejects configuration`() {
        #expect(throws: TestError.unavailable) {
            try CompilerBuildConfiguration(probe: ThrowingProbe())
        }
    }

    @Test func `contradictory endianness rejects configuration`() {
        #expect(throws: (any Error).self) {
            try CompilerBuildConfiguration(probe: ContradictoryEndiannessProbe())
        }
    }

    @Test func `contradictory pointer widths reject configuration`() {
        #expect(throws: (any Error).self) {
            try CompilerBuildConfiguration(probe: ContradictoryPointerProbe())
        }
    }

    @Test func `build configuration emits compiler conditional spellings`() throws {
        let probe = VersionProbe(language: VersionTuple(6), compiler: VersionTuple(6, 3))
        let sut = try CompilerBuildConfiguration(probe: probe)
        probe.reset()

        _ = try sut.isCustomConditionSet(name: "DEBUG")
        _ = try sut.hasFeature(name: "StrictConcurrency")
        _ = try sut.hasAttribute(name: "available")
        _ = try sut.isActiveTargetOS(name: "macOS")
        _ = try sut.isActiveTargetArchitecture(name: "arm64")
        _ = try sut.isActiveTargetEnvironment(name: "simulator")
        _ = try sut.isActiveTargetRuntime(name: "_ObjC")
        _ = try sut.isActiveTargetPointerAuthentication(name: "_arm64e")
        _ = try sut.isActiveTargetObjectFormat(name: "MachO")
        _ = try sut.canImport(
            importPath: [(TokenSyntax.identifier("Example"), "Example")],
            version: .version(VersionTuple(1, 2)),
        )

        #expect(probe.conditions == [
            "DEBUG",
            "hasFeature(StrictConcurrency)",
            "hasAttribute(available)",
            "os(macOS)",
            "arch(arm64)",
            "targetEnvironment(simulator)",
            "_runtime(_ObjC)",
            "_ptrauth(_arm64e)",
            "objectFormat(MachO)",
            "canImport(Example, _version: 1.2)",
        ])
    }
}

private enum TestError: Error {
    case unavailable
}

private final class ThrowingProbe: CompilerConditionEvaluating {
    func evaluate(_: String) throws -> Bool {
        throw TestError.unavailable
    }
}

private final class ContradictoryEndiannessProbe: CompilerConditionEvaluating {
    func evaluate(_ condition: String) -> Bool {
        condition == "_pointerBitWidth(_64)" || condition.hasPrefix("_endian(")
    }
}

private final class ContradictoryPointerProbe: CompilerConditionEvaluating {
    func evaluate(_ condition: String) -> Bool {
        condition == "_pointerBitWidth(_32)" || condition == "_pointerBitWidth(_64)"
    }
}

private final class VersionProbe: CompilerConditionEvaluating {
    private(set) var conditions: [String] = []
    private let language: VersionTuple
    private let compiler: VersionTuple

    init(language: VersionTuple, compiler: VersionTuple) {
        self.language = language
        self.compiler = compiler
    }

    func evaluate(_ condition: String) -> Bool {
        conditions.append(condition)
        return switch condition {
        case "_pointerBitWidth(_64)", "_hasAtomicBitWidth(_32)", "_hasAtomicBitWidth(_64)", "_endian(little)":
            true
        case "_endian(big)":
            false
        default:
            versionResult(condition)
        }
    }

    func reset() {
        conditions = []
    }

    private func versionResult(_ condition: String) -> Bool {
        for (kind, actual) in [("swift", language), ("compiler", compiler)] {
            let prefix = "\(kind)(>="
            guard condition.hasPrefix(prefix), condition.hasSuffix(")") else { continue }
            let start = condition.index(condition.startIndex, offsetBy: prefix.count)
            let candidate = String(condition[start ..< condition.index(before: condition.endIndex)])
            return VersionTuple(parsing: candidate).map { actual >= $0 } ?? false
        }
        return false
    }
}
