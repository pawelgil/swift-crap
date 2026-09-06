import CrapApplication
@testable import CrapCLI
import Foundation
import Testing

struct LocalCompilerContextLoaderTests {
    @Test func `relative context and paths resolve against capture root and compiler directory`() throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture) }
        let sourceDirectory = fixture.appendingPathComponent("Sources")
        try FileManager.default.createDirectory(at: sourceDirectory, withIntermediateDirectories: false)
        let source = sourceDirectory.appendingPathComponent("App.swift")
        let compiler = fixture.appendingPathComponent("swiftc")
        try Data("func run() {}".utf8).write(to: source)
        try Data().write(to: compiler)
        let contexts = [CompilerContext(
            compiler: "swiftc",
            arguments: ["-DDEBUG"],
            directory: ".",
            sources: ["Sources/App.swift"],
            moduleName: "App",
        )]
        try JSONEncoder().encode(contexts).write(to: fixture.appendingPathComponent("contexts.json"))

        let result = try LocalCompilerContextLoader().load(
            makeRequest(buildContext: "contexts.json"),
            root: fixture.path,
        )

        #expect(result == [CompilerContext(
            compiler: compiler.path,
            arguments: ["-DDEBUG"],
            directory: fixture.path,
            sources: [source.path],
            moduleName: "App",
        )])
    }

    @Test func `malformed context document is rejected`() throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture) }
        try Data("not-json".utf8).write(to: fixture.appendingPathComponent("contexts.json"))

        #expect(throws: (any Error).self) {
            try LocalCompilerContextLoader().load(makeRequest(buildContext: "contexts.json"), root: fixture.path)
        }
    }

    @Test func `compiler driver symlink is preserved`() throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture) }
        let source = try makeSource(in: fixture)
        let frontend = fixture.appendingPathComponent("swift-frontend")
        let driver = fixture.appendingPathComponent("swiftc")
        try Data().write(to: frontend)
        try FileManager.default.createSymbolicLink(at: driver, withDestinationURL: frontend)
        let contexts = [CompilerContext(
            compiler: driver.path,
            arguments: [],
            directory: fixture.path,
            sources: [source.path],
            moduleName: "App",
        )]
        try JSONEncoder().encode(contexts).write(to: fixture.appendingPathComponent("contexts.json"))

        let result = try LocalCompilerContextLoader().load(
            makeRequest(buildContext: "contexts.json"),
            root: fixture.path,
        )

        #expect(result.first?.compiler == driver.path)
    }

    @Test func `incomplete context is rejected`() throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture) }
        let contexts = [CompilerContext(
            compiler: "swiftc",
            arguments: [],
            directory: ".",
            sources: [],
            moduleName: "",
        )]
        try JSONEncoder().encode(contexts).write(to: fixture.appendingPathComponent("contexts.json"))

        #expect(throws: (any Error).self) {
            try LocalCompilerContextLoader().load(makeRequest(buildContext: "contexts.json"), root: fixture.path)
        }
    }

    private func makeFixture() throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        return directory.resolvingSymlinksInPath()
    }

    private func makeSource(in fixture: URL) throws -> URL {
        let source = fixture.appendingPathComponent("App.swift")
        try Data("func run() {}".utf8).write(to: source)
        return source
    }

    private func makeRequest(buildContext: String) -> CaptureRequest {
        CaptureRequest(
            root: ".",
            output: "receipt.json",
            coverage: ["coverage.json"],
            buildDescription: nil,
            buildContext: buildContext,
            command: ["swift", "test"],
        )
    }
}
