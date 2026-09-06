import CrapApplication
@testable import CrapCLI
import Foundation
import Testing

struct CapturePathTests {
    @Test func `preexisting coverage artifact is rejected`() throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture) }
        let coverage = fixture.appendingPathComponent("coverage.json")
        try Data().write(to: coverage)

        #expect(throws: (any Error).self) {
            try LocalCapturePathPreparer().prepare(makeRequest(root: fixture, coverage: [coverage.path]))
        }
    }

    @Test func `canonical artifact aliases are rejected`() throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture) }
        let paths = try makeAliasedOutput(in: fixture)

        #expect(throws: (any Error).self) {
            try LocalCapturePathPreparer().prepare(
                makeRequest(root: fixture, coverage: [paths.original, paths.alias]),
            )
        }
    }

    @Test func `not yet created artifact uses resolved parent path`() throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture) }
        let output = try makeAliasedOutput(in: fixture)

        let paths = try LocalCapturePathPreparer().prepare(
            makeRequest(root: fixture, coverage: [output.alias]),
        )

        #expect(try paths.coverage == [CanonicalPath().resolve(output.original)])
    }

    @Test func `relative xcode project is stored relative to capture root`() throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture) }
        let project = fixture.appendingPathComponent("App.xcodeproj")
        try FileManager.default.createDirectory(at: project, withIntermediateDirectories: false)
        let request = CaptureRequest(
            root: fixture.path,
            output: fixture.appendingPathComponent("receipt.json").path,
            coverage: [fixture.appendingPathComponent("coverage.json").path],
            buildDescription: nil,
            buildContext: nil,
            command: ["xcodebuild"],
            xcode: XcodeSelection(project: "App.xcodeproj", scheme: "App", target: "App"),
        )

        let paths = try LocalCapturePathPreparer().prepare(request)
        let expected = try CanonicalPath().resolve(project.path)

        #expect(paths.xcode?.project == expected)
    }

    @Test func `nested capture outputs are rejected`() throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture) }
        let coverage = fixture.appendingPathComponent("coverage")
        let request = CaptureRequest(
            root: fixture.path,
            output: coverage.appendingPathComponent("receipt.json").path,
            coverage: [coverage.path],
            buildDescription: nil,
            buildContext: fixture.appendingPathComponent("context.json").path,
            command: ["true"],
        )

        #expect(throws: (any Error).self) {
            try LocalCapturePathPreparer().prepare(request)
        }
    }

    private func makeFixture() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("swift-crap-path-\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        return directory.resolvingSymlinksInPath()
    }

    private func makeAliasedOutput(in root: URL) throws -> (original: String, alias: String) {
        let original = root.appendingPathComponent("outputs", isDirectory: true)
        let alias = root.appendingPathComponent("alias", isDirectory: true)
        try FileManager.default.createDirectory(at: original, withIntermediateDirectories: false)
        try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: original)
        return (
            original.appendingPathComponent("coverage.json").path,
            alias.appendingPathComponent("coverage.json").path,
        )
    }

    private func makeRequest(root: URL, coverage: [String]) -> CaptureRequest {
        CaptureRequest(
            root: root.path,
            output: root.appendingPathComponent("receipt.json").path,
            coverage: coverage,
            buildDescription: nil,
            buildContext: root.appendingPathComponent("context.json").path,
            command: ["true"],
        )
    }
}
