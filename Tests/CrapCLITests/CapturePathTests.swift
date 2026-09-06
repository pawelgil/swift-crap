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
        let privatePath = fixture.appendingPathComponent("coverage.json").path
        let temporaryAlias = privatePath.replacingOccurrences(of: "/private/tmp/", with: "/tmp/")

        #expect(throws: (any Error).self) {
            try LocalCapturePathPreparer().prepare(
                makeRequest(root: fixture, coverage: [privatePath, temporaryAlias]),
            )
        }
    }

    @Test func `not yet created artifact uses resolved parent path`() throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture) }
        let privatePath = fixture.appendingPathComponent("coverage.json").path
        let temporaryAlias = privatePath.replacingOccurrences(of: "/private/tmp/", with: "/tmp/")

        let paths = try LocalCapturePathPreparer().prepare(
            makeRequest(root: fixture, coverage: [temporaryAlias]),
        )

        #expect(try paths.coverage == [CanonicalPath().resolve(privatePath)])
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
        let directory = URL(fileURLWithPath: "/private/tmp/swift-crap-path-\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        return directory
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
