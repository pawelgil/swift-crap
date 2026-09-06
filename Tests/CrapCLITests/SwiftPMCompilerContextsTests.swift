@testable import CrapCLI
import Foundation
import Testing

struct SwiftPMCompilerContextsTests {
    @Test func `decoded context includes module name compiler argument`() throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture) }
        let description = try makeDescription(in: fixture)

        let contexts = try SwiftPMCompilerContexts().read(at: description.path, root: fixture.path)

        let context = try #require(contexts.first)
        #expect(context.arguments == [
            "-module-name", "Logic",
            "-I", fixture.appendingPathComponent("Modules").path,
            "-swift-version", "6",
            "-DAUDIT_ACTIVE",
        ])
    }

    @Test func `decoded context preserves current module conditional`() throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture) }
        let description = try makeDescription(in: fixture)
        let contexts = try SwiftPMCompilerContexts().read(at: description.path, root: fixture.path)
        let context = try #require(contexts.first)

        let result = try CompilerProbe(context: context).evaluate("canImport(Logic)")

        #expect(result)
    }

    private func makeFixture() throws -> URL {
        let fixture = FileManager.default.temporaryDirectory
            .appendingPathComponent("swift-crap-context-\(UUID())", isDirectory: true)
        try FileManager.default.createDirectory(at: fixture, withIntermediateDirectories: false)
        return fixture.resolvingSymlinksInPath()
    }

    private func makeDescription(in fixture: URL) throws -> URL {
        let description = fixture.appendingPathComponent("description.json")
        let modules = fixture.appendingPathComponent("Modules").path
        let source = fixture.appendingPathComponent("Decision.swift").path
        let compiler = try swiftCompiler()
        let data = try JSONSerialization.data(withJSONObject: [
            "swiftCommands": [
                "C.Logic.module": [
                    "executable": compiler,
                    "importPath": modules,
                    "moduleName": "Logic",
                    "otherArguments": ["-swift-version", "6", "-DAUDIT_ACTIVE"],
                    "sources": [source],
                ],
            ],
        ])
        try data.write(to: description)
        return description
    }

    private func swiftCompiler() throws -> String {
        let path = try #require(ProcessInfo.processInfo.environment["PATH"])
        let candidates = path.split(separator: ":").map {
            URL(fileURLWithPath: String($0), isDirectory: true).appendingPathComponent("swiftc").path
        }
        return try #require(candidates.first(where: FileManager.default.isExecutableFile(atPath:)))
    }
}
